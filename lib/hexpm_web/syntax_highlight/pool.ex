defmodule HexpmWeb.SyntaxHighlight.Pool do
  @moduledoc """
  A pool of `lumis serve` processes, each behind an Erlang port.

  A caller checks out a port, which is connected to it for the request, sends
  the source, and waits up to `:timeout`. On a reply it connects the port back
  to the pool. On a timeout it closes the port: `lumis serve` exits when its
  stdin closes, also in the middle of a highlight, and the pool starts another.
  The same happens if the caller dies, since a port closes with its owner. The
  per-request CPU limit, which the kernel enforces, stops a process whose stdin
  is never read.

  Workers whose peak memory passed `:recycle_rss_mb` are replaced after the
  request.

  Languages a worker did not have are given to `HexpmWeb.SyntaxHighlight.Fetcher`.
  """

  @behaviour NimblePool

  require Logger

  alias HexpmWeb.SyntaxHighlight.{Fetcher, Launcher, Output}

  @type error() ::
          :not_cached
          | :timeout
          | :queue_timeout
          | :unavailable
          | :rejected_output
          | {:exit, non_neg_integer() | :closed}
          | {:lumis, String.t()}

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Starts the pool. Options are those of `config :hexpm, HexpmWeb.SyntaxHighlight`,
  which they default to, plus `:name` and `:fetcher`.

  It checks that `lumis serve` starts under its sandbox first, see
  `HexpmWeb.SyntaxHighlight.Launcher.check/1`, and does not start without it.
  """
  def start_link(opts) do
    config = config(opts)

    NimblePool.start_link(
      worker: {__MODULE__, config},
      pool_size: Keyword.fetch!(config, :workers),
      name: Keyword.fetch!(config, :name)
    )
  end

  @doc """
  Highlights `source` as html-linked HTML. `language` is a language name or a
  file path.

  Options override the pool's configuration for `:timeout`, `:queue_timeout`,
  `:cpu_limit_ms` and `:match_limit`.
  """
  @spec highlight(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def highlight(source, language, opts \\ []) do
    config = config(opts)

    request =
      Lumis.Port.request(source, language,
        cpu_limit_ms: Keyword.fetch!(config, :cpu_limit_ms),
        match_limit: Keyword.get(config, :match_limit, 0)
      )

    config
    |> Keyword.fetch!(:name)
    |> NimblePool.checkout!(
      :checkout,
      fn {pool, _ref}, port -> run(port, pool, request, Keyword.fetch!(config, :timeout)) end,
      Keyword.fetch!(config, :queue_timeout)
    )
    |> fetch_missing(Keyword.fetch!(config, :fetcher))
  catch
    :exit, {:timeout, {NimblePool, :checkout, _}} -> {:error, :queue_timeout}
    :exit, {:noproc, {NimblePool, :checkout, _}} -> {:error, :unavailable}
  end

  defp config(opts) do
    :hexpm
    |> Application.fetch_env!(HexpmWeb.SyntaxHighlight)
    |> Keyword.merge(name: __MODULE__, fetcher: Fetcher, data_dir: Lumis.Port.data_dir())
    |> Keyword.merge(opts)
  end

  defp run(port, pool, request, timeout) do
    Port.command(port, request)

    receive do
      {^port, {:data, reply}} ->
        handle_reply(decode_reply(reply), port, pool)

      {^port, {:exit_status, status}} ->
        Launcher.close(port)
        {{:error, {:exit, status}}, :remove}
    after
      timeout ->
        Launcher.close(port)
        {{:error, :timeout}, :remove}
    end
  rescue
    # The process exited after it was checked out and before the request.
    ArgumentError ->
      Launcher.close(port)
      {{:error, {:exit, :closed}}, :remove}
  end

  defp decode_reply(reply) do
    Lumis.Port.decode_reply(reply)
  rescue
    _error -> :malformed
  end

  defp handle_reply(:malformed, port, _pool) do
    Launcher.close(port)
    {{:error, :rejected_output}, :remove}
  end

  defp handle_reply({:ok, html, missing, max_rss_kb}, port, pool) do
    if Output.valid?(html) do
      {{:ok, html, missing}, give_back(port, pool, max_rss_kb)}
    else
      Launcher.close(port)
      {{:error, :rejected_output}, :remove}
    end
  end

  defp handle_reply({:not_cached, language, max_rss_kb}, port, pool) do
    {{:not_cached, language}, give_back(port, pool, max_rss_kb)}
  end

  defp handle_reply({:error, message, max_rss_kb}, port, pool) do
    {{:error, {:lumis, message}}, give_back(port, pool, max_rss_kb)}
  end

  # Connects the port back to the pool, and drops anything it sent the caller
  # before that, so nothing from it reaches the caller's mailbox later.
  defp give_back(port, pool, max_rss_kb) do
    Port.connect(port, pool)
    Process.unlink(port)
    Launcher.flush(port)
    {:ok, max_rss_kb}
  rescue
    # The process exited after it replied.
    ArgumentError ->
      Launcher.close(port)
      :remove
  end

  defp fetch_missing({:ok, html, []}, _fetcher), do: {:ok, html}

  defp fetch_missing({:ok, html, missing}, fetcher) do
    Fetcher.fetch(fetcher, missing)
    {:ok, html}
  end

  defp fetch_missing({:not_cached, language}, fetcher) do
    Fetcher.fetch(fetcher, [language])
    {:error, :not_cached}
  end

  defp fetch_missing({:error, _reason} = error, _fetcher), do: error

  @impl NimblePool
  def init_pool(config) do
    case Launcher.check(config) do
      :ok ->
        {:ok,
         %{
           wrapper: Launcher.wrapper(config),
           data_dir: Keyword.fetch!(config, :data_dir),
           preload: Keyword.fetch!(config, :preload),
           recycle_kb: Keyword.fetch!(config, :recycle_rss_mb) * 1024
         }}

      {:error, reason} ->
        Logger.error("Syntax highlighting is off, lumis serve failed its start check: #{reason}")
        :ignore
    end
  end

  @impl NimblePool
  def init_worker(state) do
    port =
      Lumis.Port.open(
        wrapper: state.wrapper,
        env: Launcher.env(),
        data_dir: state.data_dir,
        preload: state.preload
      )

    {:ok, port, state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, {client, _ref}, port, state) do
    Port.connect(port, client)
    {:ok, port, port, state}
  rescue
    # The process exited while idle and its exit has not been handled yet.
    ArgumentError -> {:remove, :exit, state}
  end

  @impl NimblePool
  def handle_checkin({:ok, max_rss_kb}, _from, port, state) do
    if max_rss_kb > state.recycle_kb do
      {:remove, :recycle, state}
    else
      {:ok, port, state}
    end
  end

  def handle_checkin(:remove, _from, _port, state) do
    {:remove, :closed, state}
  end

  @impl NimblePool
  def handle_info({port, {:exit_status, _status}}, port), do: {:remove, :exit}
  def handle_info({:EXIT, port, _reason}, port), do: {:remove, :exit}
  def handle_info(_message, port), do: {:ok, port}

  @impl NimblePool
  def terminate_worker(_reason, port, state) do
    Launcher.close(port)
    {:ok, state}
  end
end
