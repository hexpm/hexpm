defmodule HexpmWeb.SyntaxHighlight do
  use GenServer
  require Logger

  alias Lumis.Formatter.HTML

  @budget [time_limit: 300, match_limit: 4096]
  @linked_attrs Map.new(HTML.classes(), fn {scope, class} -> {scope, ~s|class="#{class}"|} end)
  @timeout 1_000
  @slow_ttl :timer.hours(1)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def budget, do: @budget

  def highlight(source, language, label, opts \\ []) do
    budget = Keyword.get(opts, :budget, @budget)

    run(
      {language, source},
      fn ->
        source
        |> Lumis.highlight(formatter: {:html_linked, language: language}, budget: budget)
        |> or_plain(label, fn ->
          Lumis.highlight!(source, formatter: {:html_linked, language: "plaintext"})
        end)
      end,
      fn -> plain_source(source) end,
      label,
      opts
    )
  end

  def highlight_lines(lines, language, label, opts \\ [])

  def highlight_lines([], _language, _label, _opts), do: []

  def highlight_lines(lines, language, label, opts) when is_list(lines) do
    budget = Keyword.get(opts, :budget, @budget)

    run(
      {language, lines},
      fn ->
        source = Enum.map_join(lines, &(&1 <> "\n"))

        events =
          source
          |> Lumis.highlight_events(language, budget: budget)
          |> or_plain(label, fn -> Lumis.highlight_events!(source, "plaintext") end)

        HTML.render_lines_from_events(source, events, @linked_attrs)
      end,
      fn -> Enum.map(lines, &escape/1) end,
      label,
      opts
    )
  end

  @doc false
  def or_plain({:ok, result}, _label, _fun), do: result

  def or_plain({:error, error}, label, fun) do
    Logger.warning("Failed to highlight #{label}: #{Exception.message(error)}")
    fun.()
  end

  @doc """
  Runs `function` in a task and answers `fallback` when it can't finish in time.

  A highlight that runs out of time keeps running, because killing its process
  does not stop the NIF, and it holds one of `:max_concurrency` slots until it
  returns. With every slot taken, and for an hour after `key` ran out of time,
  this answers `fallback` without starting the work.
  """
  def run(key, function, fallback, label, opts \\ [])
      when is_function(function, 0) and is_function(fallback, 0) do
    table = Keyword.get(opts, :table, __MODULE__)
    timeout = Keyword.get(opts, :timeout, @timeout)
    max_concurrency = Keyword.get_lazy(opts, :max_concurrency, &max_concurrency/0)
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(key))

    cond do
      slow?(table, digest) ->
        fallback.()

      not acquire(table, max_concurrency) ->
        Logger.warning(
          "Skipped highlighting #{label}: #{max_concurrency} highlights already running"
        )

        fallback.()

      true ->
        await(table, digest, function, fallback, label, timeout)
    end
  end

  defp max_concurrency() do
    Application.get_env(:hexpm, :syntax_highlight_max_concurrency) ||
      max(div(:erlang.system_info(:dirty_cpu_schedulers_online), 2), 1)
  end

  defp await(table, digest, function, fallback, label, timeout) do
    task =
      Task.Supervisor.async_nolink(Hexpm.Tasks, fn ->
        try do
          function.()
        after
          :ets.update_counter(table, :running, {2, -1})
        end
      end)

    case Task.yield(task, timeout) || Task.ignore(task) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.warning("Failed to highlight #{label}: #{inspect(reason)}")
        fallback.()

      nil ->
        :ets.insert(table, {digest, System.monotonic_time(:millisecond) + @slow_ttl})
        Logger.warning("Failed to highlight #{label}: timed out after #{timeout}ms")
        fallback.()
    end
  end

  defp acquire(table, max_concurrency) do
    running = :ets.update_counter(table, :running, {2, 1})

    if max_concurrency == :infinity or running <= max_concurrency do
      true
    else
      :ets.update_counter(table, :running, {2, -1})
      false
    end
  end

  defp slow?(table, digest) do
    case :ets.lookup(table, digest) do
      [{^digest, expires_at}] -> expires_at > System.monotonic_time(:millisecond)
      [] -> false
    end
  end

  @impl true
  def init(table) do
    :ets.new(table, [:named_table, :public, :set, write_concurrency: true])
    :ets.insert(table, {:running, 0})
    schedule_sweep()
    {:ok, table}
  end

  @impl true
  def handle_info(:sweep, table) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(table, [{{:"$1", :"$2"}, [{:is_binary, :"$1"}, {:<, :"$2", now}], [true]}])
    schedule_sweep()
    {:noreply, table}
  end

  defp schedule_sweep() do
    Process.send_after(self(), :sweep, @slow_ttl)
  end

  defp plain_source(source) do
    lines =
      source
      |> String.replace(~r/\r?\n\z/, "")
      |> String.split(["\r\n", "\n"])
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {line, number} ->
        ~s(<span class="l-line" data-line="#{number}">#{escape(line)}</span>)
      end)

    ~s(<pre class="lumis"><code class="language-plaintext" translate="no" tabindex="0">) <>
      lines <> "</code></pre>"
  end

  defp escape(source) do
    source
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
