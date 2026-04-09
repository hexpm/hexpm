defmodule HexpmWeb.Readme.TaskList do
  @moduledoc """
  Converts GFM-style task list checkboxes in an Earmark AST into
  `<input type="checkbox">` elements.

  Earmark parses `- [ ] item` and `- [x] item` as plain text inside
  list items. This module walks the AST and replaces the checkbox
  text markers with disabled checkbox input nodes.
  """

  @checkbox_pattern ~r/^\[([ xX])\]\s?/

  def convert(ast) do
    Enum.map(ast, &convert_node/1)
  end

  defp convert_node({"li", attrs, children, meta}) do
    {"li", attrs, convert_li_children(children), meta}
  end

  defp convert_node({tag, attrs, children, meta}) do
    {tag, attrs, convert(children), meta}
  end

  defp convert_node(text) when is_binary(text), do: text

  defp convert_li_children([text | rest]) when is_binary(text) do
    case Regex.run(@checkbox_pattern, text) do
      [match, marker] ->
        remaining = String.slice(text, String.length(match)..-1//1)
        [checkbox_input(marker) | prepend_if_nonempty(remaining, rest)]

      nil ->
        [text | rest]
    end
  end

  defp convert_li_children([{"p", p_attrs, [text | p_rest], p_meta} | rest])
       when is_binary(text) do
    case Regex.run(@checkbox_pattern, text) do
      [match, marker] ->
        remaining = String.slice(text, String.length(match)..-1//1)
        p_children = [checkbox_input(marker) | prepend_if_nonempty(remaining, p_rest)]
        [{"p", p_attrs, p_children, p_meta} | rest]

      nil ->
        [{"p", p_attrs, [text | p_rest], p_meta} | rest]
    end
  end

  defp convert_li_children(children), do: children

  defp checkbox_input(" ") do
    {"input", [{"type", "checkbox"}, {"disabled", "disabled"}], [], %{}}
  end

  defp checkbox_input(_checked) do
    {"input", [{"type", "checkbox"}, {"checked", "checked"}, {"disabled", "disabled"}], [], %{}}
  end

  defp prepend_if_nonempty("", rest), do: rest
  defp prepend_if_nonempty(text, rest), do: [text | rest]
end
