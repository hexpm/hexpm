defmodule HexpmWeb.SyntaxHighlight do
  use GenServer
  require Logger

  @timeout 1_000
  @slow_ttl :timer.hours(1)
  @line_pattern ~r/<div class="l-line" data-line="\d+">(.*?)\n?<\/div>/s

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc """
  Loads the highlighter so the first request does not have to.

  The NIF is 143 MB, and the timeout above is sized for highlighting a file, not
  for opening it. Whichever request arrived first used to pay that load out of
  its own budget and fall back to unhighlighted source when it ran out.
  """
  def warm() do
    Lumis.highlight!("", formatter: {:html_linked, language: "warm.ex"})
    :ok
  rescue
    error -> Logger.warning("Failed to warm the highlighter: #{Exception.message(error)}")
  end

  def highlight(source, language, label) do
    run(
      {language, source},
      fn -> Lumis.highlight!(source, formatter: {:html_linked, language: language}) end,
      fn -> plain_source(source) end,
      label
    )
  end

  def highlight_lines([], _language, _label), do: []

  def highlight_lines(lines, language, label) when is_list(lines) do
    run(
      {language, lines},
      fn ->
        highlighted =
          lines
          |> Enum.join("\n")
          |> Lumis.highlight!(formatter: {:html_linked, language: language})

        fragments =
          @line_pattern
          |> Regex.scan(highlighted, capture: :all_but_first)
          |> List.flatten()

        if length(fragments) == length(lines) do
          fragments
        else
          raise "Lumis returned #{length(fragments)} lines for #{length(lines)} source lines"
        end
      end,
      fn -> Enum.map(lines, &escape/1) end,
      label
    )
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
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join(fn {line, number} ->
        ~s(<div class="l-line" data-line="#{number}">#{escape(line)}</div>)
      end)

    ~s(<pre class="lumis"><code>#{lines}</code></pre>)
  end

  defp escape(source) do
    source
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
