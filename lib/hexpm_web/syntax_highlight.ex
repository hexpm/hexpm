defmodule HexpmWeb.SyntaxHighlight do
  require Logger

  @timeout 1_000
  @line_pattern ~r/<div class="l-line" data-line="\d+">(.*?)\n?<\/div>/s

  def highlight(source, language, label) do
    run(
      fn -> Lumis.highlight!(source, formatter: {:html_linked, language: language}) end,
      fn -> plain_source(source) end,
      label
    )
  end

  def highlight_lines([], _language, _label), do: []

  def highlight_lines(lines, language, label) when is_list(lines) do
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
      fn -> Enum.map(lines, &escape/1) end,
      label
    )
  end

  @doc false
  def run(function, fallback, label, timeout \\ @timeout)
      when is_function(function, 0) and is_function(fallback, 0) do
    task = Task.Supervisor.async_nolink(Hexpm.Tasks, function)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      result ->
        Logger.warning("Failed to highlight #{label}: #{inspect(result)}")
        fallback.()
    end
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
