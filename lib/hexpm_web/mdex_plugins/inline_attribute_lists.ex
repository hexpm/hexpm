defmodule HexpmWeb.MDExPlugins.InlineAttributeLists do
  @moduledoc """
  MDEx AST plugin that implements a subset of Inline Attribute List (IAL) syntax.

  Supports `{: .class1 .class2}` on a line immediately after a block element.
  Currently handles tables, where the IAL row is stripped and the classes are
  applied to the `<table>` element via a raw HTML wrapper.

  Earmark supports this syntax natively; this plugin provides compatibility when
  migrating to MDEx/comrak which does not.
  """

  @ial_regex ~r/^\{:\s*((?:\.[a-zA-Z0-9_-]+\s*)+)\}$/

  @doc """
  Transforms an MDEx AST node, applying IAL classes where found.
  Pass this to `MDEx.traverse_and_update/2`.
  """
  def transform(%MDEx.Table{nodes: nodes} = table) do
    case pop_ial_row(nodes) do
      {nil, _} ->
        table

      {classes, remaining_nodes} ->
        html = table_with_classes(%{table | nodes: remaining_nodes}, classes)
        %MDEx.HtmlBlock{literal: html}
    end
  end

  def transform(node), do: node

  # Finds and removes a trailing IAL row from a table's nodes.
  # Returns {classes_string_or_nil, remaining_nodes}.
  defp pop_ial_row(nodes) do
    case List.last(nodes) do
      %MDEx.TableRow{
        header: false,
        nodes: [%MDEx.TableCell{nodes: [%MDEx.Text{literal: text}]} | _]
      } ->
        case Regex.run(@ial_regex, String.trim(text)) do
          [_, classes_str] ->
            classes =
              classes_str
              |> String.split()
              |> Enum.map(&String.trim_leading(&1, "."))
              |> Enum.join(" ")

            {classes, List.delete_at(nodes, -1)}

          nil ->
            {nil, nodes}
        end

      _ ->
        {nil, nodes}
    end
  end

  defp table_with_classes(table, classes) do
    inner =
      table
      |> MDEx.to_html!()
      |> String.trim()
      # Replace opening <table> tag with one that has the classes
      |> String.replace(~r/\A<table>/, ~s|<table class="#{classes}">|)

    inner <> "\n"
  end
end
