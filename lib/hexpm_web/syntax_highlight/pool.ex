defmodule HexpmWeb.SyntaxHighlight.Pool do
  @moduledoc """
  A pool of `lumis serve` processes, each behind an Erlang port, with every
  language hexpm depends on loaded before it takes a request.

  A caller checks out a port, which is connected to it for the request, sends
  the source, and waits up to `:timeout`. On a reply it connects the port back
  to the pool. On a timeout it closes the port: `lumis serve` exits when its
  stdin closes, also in the middle of a highlight, and the pool starts another.
  The same happens if the caller dies, since a port closes with its owner. The
  per-request CPU limit, which the kernel enforces, stops a process whose stdin
  is never read.

  Each process runs under `nice`, and on Linux with a heap limit, so an
  allocation fails in that process before the container reaches its memory
  limit. Workers whose peak memory passed `:recycle_rss_mb` are replaced after
  the request.
  """

  @behaviour NimblePool

  require Logger

  @ready_timeout 60_000

  @type error() ::
          :timeout
          | :queue_timeout
          | :unavailable
          | :malformed_reply
          | {:exit, non_neg_integer()}
          | {:lumis, String.t()}

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Starts the pool. Options are those of `config :hexpm, HexpmWeb.SyntaxHighlight`,
  which they default to, plus `:name`.

  It first starts one `lumis serve` that loads every language without the heap
  limit, and does not start if that one does not answer. Compiling the parsers
  takes about three times the memory loading compiled ones does, so that one
  compiles them into the cache once, and the processes in the pool load them
  from there.
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
  Highlights `source` as an html-linked `:document`, or as `:lines` of
  html-linked fragments. `language` is a language name or a file path.

  Options override the pool's configuration for `:timeout`, `:queue_timeout`
  and `:cpu_limit_ms`, and take the budget's `:time_limit` and `:match_limit`.
  """
  @spec highlight(Lumis.Port.kind(), String.t(), String.t(), keyword()) ::
          {:ok, String.t() | [String.t()]} | {:error, error()}
  def highlight(kind, source, language, opts \\ []) do
    config = config(opts)

    request =
      Lumis.Port.request(kind, source, language,
        match_limit: Keyword.get(config, :match_limit, 0),
        time_limit: Keyword.get(config, :time_limit, 0),
        cpu_limit_ms: Keyword.fetch!(config, :cpu_limit_ms)
      )

    config
    |> Keyword.fetch!(:name)
    |> NimblePool.checkout!(
      :checkout,
      fn {pool, _ref}, port ->
        run(port, pool, kind, request, Keyword.fetch!(config, :timeout))
      end,
      Keyword.fetch!(config, :queue_timeout)
    )
  catch
    :exit, {:timeout, {NimblePool, :checkout, _}} -> {:error, :queue_timeout}
    :exit, {:noproc, {NimblePool, :checkout, _}} -> {:error, :unavailable}
  end

  defp config(opts) do
    :hexpm
    |> Application.fetch_env!(HexpmWeb.SyntaxHighlight)
    |> Keyword.put(:name, __MODULE__)
    |> Keyword.merge(opts)
  end

  # A port that already exited drops the command, and its exit status is
  # already on its way here, since the port was connected to this process.
  defp run(port, pool, kind, request, timeout) do
    send(port, {self(), {:command, request}})

    receive do
      {^port, {:data, reply}} ->
        handle_reply(Lumis.Port.decode_reply(reply, kind), port, pool)

      {^port, {:exit_status, status}} ->
        close(port)
        {{:error, {:exit, status}}, :remove}
    after
      timeout ->
        close(port)
        {{:error, :timeout}, :remove}
    end
  end

  defp handle_reply({:ok, result, max_rss_kb}, port, pool) do
    {{:ok, result}, give_back(port, pool, max_rss_kb)}
  end

  defp handle_reply({:error, message, max_rss_kb}, port, pool) do
    {{:error, {:lumis, message}}, give_back(port, pool, max_rss_kb)}
  end

  defp handle_reply(_reply, port, _pool) do
    close(port)
    {{:error, :malformed_reply}, :remove}
  end

  # Connects the port back to the pool, and drops anything it sent the caller
  # before that, so nothing from it reaches the caller's mailbox later.
  defp give_back(port, pool, max_rss_kb) do
    if connect(port, pool) do
      Process.unlink(port)
      flush(port)
      {:ok, max_rss_kb}
    else
      close(port)
      :remove
    end
  end

  # `Port.connect/2` raises only when the port is closed.
  defp connect(port, pid) do
    Port.connect(port, pid)
  rescue
    ArgumentError -> false
  end

  # `Port.close/1` raises only when the port is already closed.
  defp close(port) do
    Process.unlink(port)

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    flush(port)
  end

  defp flush(port) do
    receive do
      {^port, _message} -> flush(port)
      {:EXIT, ^port, _reason} -> flush(port)
    after
      0 -> :ok
    end
  end

  @impl NimblePool
  def init_pool(config) do
    state = %{
      wrapper: [nice!(), "-n", to_string(Keyword.fetch!(config, :nice)), "--"],
      max_data_mb: if(match?({:unix, :linux}, :os.type()), do: config[:max_data_mb]),
      recycle_kb: Keyword.fetch!(config, :recycle_rss_mb) * 1024
    }

    port = Lumis.Port.open(wrapper: state.wrapper, preload_installed: true)
    ready = Lumis.Port.await_ready(port, @ready_timeout)
    close(port)

    case ready do
      {:ok, _max_rss_kb} ->
        {:ok, state}

      {:error, reason} ->
        Logger.error("Syntax highlighting is off, lumis serve did not start: #{inspect(reason)}")
        :ignore
    end
  end

  defp nice!() do
    System.find_executable("nice") || raise "nice is not on the PATH"
  end

  # Loading every language takes a while, so a process joins the pool only
  # once it says it is ready, and no request waits on it.
  @impl NimblePool
  def init_worker(state) do
    pool = self()
    {:async, fn -> start_worker(state, pool) end, state}
  end

  defp start_worker(state, pool) do
    port =
      Lumis.Port.open(
        wrapper: state.wrapper,
        max_data_mb: state.max_data_mb,
        preload_installed: true
      )

    with {:ok, _max_rss_kb} <- Lumis.Port.await_ready(port, @ready_timeout),
         true <- connect(port, pool) do
      Process.unlink(port)
      port
    else
      error ->
        close(port)
        exit({:lumis_serve_not_ready, error})
    end
  end

  @impl NimblePool
  def handle_checkout(:checkout, {client, _ref}, port, state) do
    if connect(port, client) do
      {:ok, port, port, state}
    else
      {:remove, :exit, state}
    end
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
    close(port)
    {:ok, state}
  end
end
