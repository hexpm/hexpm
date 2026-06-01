defmodule HexpmWeb.MDExPlugins.HeadingAnchors do
  @moduledoc ~S"""
  MDEx AST plugin that rewrites headings into anchored sections.

  For each `<h{level}>` whose level is in `:levels`, the heading is replaced
  with an HTML block of the form:

      <h{level} id="{slug}" class="section-heading">
        <a href="#{slug}" class="hover-link">{icon}</a> {inner}
      </h{level}>

  The slug is derived from the heading's text content.
  """

  @doc """
  Returns a `MDEx.traverse_and_update/2` callback that anchors headings whose
  level is in `opts[:levels]`.

  Options:

    * `:levels` (required) - list of heading levels to anchor (e.g. `[3, 4]`).
    * `:hover_link` - when `true` (default), prepend an `<a class="hover-link">`
      with the `:link` heroicon to each anchored heading. When `false`, only
      the heading's `id` and `class` are emitted.
  """
  def transform(opts) when is_list(opts) do
    levels = Keyword.fetch!(opts, :levels)
    hover_link? = Keyword.get(opts, :hover_link, true)
    fn node -> do_transform(node, levels, hover_link?) end
  end

  defp hover_link_html(anchor) do
    icon_html =
      HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
      |> Phoenix.HTML.safe_to_string()

    ~s|<a href="##{anchor}" class="hover-link">#{icon_html}</a> |
  end

  defp do_transform(%MDEx.Heading{level: level, nodes: children} = node, levels, hover_link?) do
    if level in levels do
      anchor = slugify(extract_text(children))

      inner_html =
        %{node | nodes: children}
        |> MDEx.to_html!()
        |> String.trim()
        |> String.replace(~r/\A<h#{level}>(.*)<\/h#{level}>\z/s, "\\1")

      link_html = if hover_link?, do: hover_link_html(anchor), else: ""

      %MDEx.HtmlBlock{
        literal:
          ~s|<h#{level} id="#{anchor}" class="section-heading">#{link_html}#{inner_html}</h#{level}>\n|
      }
    else
      node
    end
  end

  defp do_transform(node, _levels, _hover_link?), do: node

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(" ", "-")
    |> String.replace(~r/[^a-zA-Z0-9\-]/, "")
  end

  defp extract_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &extract_text/1)
  defp extract_text(%{nodes: children}), do: extract_text(children)
  defp extract_text(%MDEx.Text{literal: text}), do: text
  defp extract_text(%MDEx.Code{literal: text}), do: text
  defp extract_text(_), do: ""
end
