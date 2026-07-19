defmodule HexpmWeb.SyntaxHighlight do
  require Logger

  @line_pattern ~r/<div class="l-line" data-line="\d+">(.*?)\n?<\/div>/s

  def highlight(source, language, label) do
    fallback = fn -> plain_source(source) end

    if within_limits?(source) do
      run(
        fn -> Lumis.highlight!(source, formatter: {:html_linked, language: language}) end,
        fallback,
        label
      )
    else
      fallback.()
    end
  end

  def highlight_lines([], _language, _label), do: []

  def highlight_lines(lines, language, label) when is_list(lines) do
    fallback = fn -> Enum.map(lines, &escape/1) end

    if lines_within_limits?(lines) do
      run(
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
        fallback,
        label
      )
    else
      fallback.()
    end
  end

  @doc false
  def run(
        function,
        fallback,
        label,
        timeout \\ config()[:timeout],
        supervisor \\ HexpmWeb.SyntaxHighlight.TaskSupervisor
      )
      when is_function(function, 0) and is_function(fallback, 0) do
    case run_task(function, supervisor, timeout) do
      {:ok, result} ->
        result

      result ->
        Logger.warning("Failed to highlight #{label}: #{inspect(result)}")
        fallback.()
    end
  end

  defp run_task(function, supervisor, timeout) do
    owner = self()
    ref = make_ref()

    case Task.Supervisor.start_child(supervisor, fn -> send(owner, {ref, function.()}) end) do
      {:ok, pid} -> await(pid, ref, timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  defp await(pid, ref, timeout) do
    monitor = Process.monitor(pid)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        {:ok, result}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, reason}
    after
      timeout ->
        Process.exit(pid, :kill)
        receive do: ({:DOWN, ^monitor, :process, ^pid, _reason} -> :ok)
        {:error, :timeout}
    end
  end

  defp within_limits?(source) do
    config = config()
    byte_size(source) <= config[:max_size] and line_count_at_most?(source, config[:max_lines])
  end

  defp lines_within_limits?(lines) do
    config = config()

    length(lines) <= config[:max_lines] and
      Enum.reduce(lines, -1, fn line, size -> size + byte_size(line) + 1 end) <= config[:max_size]
  end

  defp line_count_at_most?(source, max_lines), do: count_lines(source, max_lines - 1)

  defp count_lines(_source, remaining) when remaining < 0, do: false

  defp count_lines(source, remaining) do
    case :binary.match(source, "\n") do
      :nomatch ->
        true

      {index, 1} ->
        count_lines(
          binary_part(source, index + 1, byte_size(source) - index - 1),
          remaining - 1
        )
    end
  end

  defp config, do: Application.fetch_env!(:hexpm, __MODULE__)

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
