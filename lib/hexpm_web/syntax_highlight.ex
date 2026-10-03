defmodule HexpmWeb.SyntaxHighlight do
  require Logger

  alias Lumis.Formatter.HTML

  @budget [time_limit: to_timeout(second: 1), match_limit: 4096]
  @linked_attrs Map.new(HTML.classes(), fn {scope, class} -> {scope, ~s|class="#{class}"|} end)

  def highlight(source, language, label, budget \\ @budget) do
    source
    |> Lumis.highlight(formatter: {:html_linked, language: language}, budget: budget)
    |> or_plain(label, fn ->
      Lumis.highlight!(source, formatter: {:html_linked, language: "plaintext"})
    end)
  end

  def highlight_lines(lines, language, label, budget \\ @budget)

  def highlight_lines([], _language, _label, _budget), do: []

  def highlight_lines(lines, language, label, budget) when is_list(lines) do
    source = Enum.map_join(lines, &(&1 <> "\n"))

    events =
      source
      |> Lumis.highlight_events(language, budget: budget)
      |> or_plain(label, fn -> Lumis.highlight_events!(source, "plaintext") end)

    HTML.render_lines_from_events(source, events, @linked_attrs)
  end

  @doc false
  def or_plain({:ok, result}, _label, _fun), do: result

  def or_plain({:error, error}, label, fun) do
    Logger.warning("Failed to highlight #{label}: #{Exception.message(error)}")
    fun.()
  end
end
