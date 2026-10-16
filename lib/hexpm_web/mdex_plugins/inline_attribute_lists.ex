defmodule HexpmWeb.MDExPlugins.InlineAttributeLists do
  @moduledoc """
  MDEx AST plugin that implements a subset of Inline Attribute List (IAL) syntax.

  Supports `{: .class1 .class2}` on a line immediately after a block element.
  Currently handles tables, where the IAL row is stripped and the classes are
  applied to the `<table>` element: `transform/1` marks the table in the AST
  and `apply_classes/1` adds the classes to the rendered HTML.

  Earmark supports this syntax natively; this plugin provides compatibility when
  migrating to MDEx/comrak which does not.
  """

  @ial_regex ~r/^\{:\s*((?:\.[a-zA-Z0-9_-]+\s*)+)\}$/

  # Raw HTML can write the same marker, which gives it a class it could have
  # written directly.
  @marker "table-classes:"

  @doc """
  Transforms an MDEx AST node, marking the tables among its children that end
  in an IAL row. Pass this to `MDEx.traverse_and_update/2` and the rendered
  HTML to `apply_classes/1`. The document must render with
  `render: [unsafe: true]`, or the markers are omitted with the rest of the raw
  HTML.
  """
  def transform(%{nodes: nodes} = node) do
    %{node | nodes: Enum.flat_map(nodes, &mark_table/1)}
  end

  def transform(node), do: node

  @doc """
  Adds the classes to every table `transform/1` marked.
  """
  def apply_classes(html) when is_binary(html) do
    Regex.replace(
      ~r/<!--#{@marker}([a-zA-Z0-9_\- ]+)-->\n<table>/,
      html,
      ~s|<table class="\\1">|
    )
  end

  defp mark_table(%MDEx.Table{nodes: nodes} = table) do
    case pop_ial_row(nodes) do
      {nil, _} ->
        [table]

      {classes, remaining_nodes} ->
        [
          %MDEx.HtmlBlock{literal: "<!--#{@marker}#{classes}-->\n"},
          %{table | nodes: remaining_nodes}
        ]
    end
  end

  defp mark_table(node), do: [node]

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
end
