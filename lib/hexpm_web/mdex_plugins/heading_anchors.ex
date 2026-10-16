defmodule HexpmWeb.MDExPlugins.HeadingAnchors do
  @moduledoc ~S"""
  MDEx AST plugin that rewrites headings into anchored sections.

  Each `<h{level}>` whose level is in `:levels` renders as:

      <h{level} id="{slug}" class="section-heading">
        <a href="#{slug}" class="hover-link">{icon}</a> {inner}
      </h{level}>

  The slug is derived from the heading's text content. `transform/1` marks the
  headings in the AST and `anchor/1` adds the attributes to the rendered HTML,
  so the document renders once however many headings it has.
  """

  # Raw HTML can write the same marker, which gives it an id and class it
  # could have written directly.
  @marker "heading-anchor:"

  @doc """
  Returns a `MDEx.traverse_and_update/2` callback that marks headings whose
  level is in `opts[:levels]`. Pass the rendered HTML to `anchor/1`. The
  document must render with `render: [unsafe: true]`, or the markers are
  omitted with the rest of the raw HTML.

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

  @doc """
  Adds the `id` and `class` to every heading `transform/1` marked.
  """
  def anchor(html) when is_binary(html) do
    Regex.replace(
      ~r/<h([1-6])><!--#{@marker}([a-zA-Z0-9\-]*)-->/,
      html,
      ~s|<h\\1 id="\\2" class="section-heading">|
    )
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
      marker = %MDEx.HtmlInline{literal: "<!--#{@marker}#{anchor}-->"}

      link =
        if hover_link?, do: [%MDEx.HtmlInline{literal: hover_link_html(anchor)}], else: []

      %{node | nodes: [marker | link] ++ children}
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
