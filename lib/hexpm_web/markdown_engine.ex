defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  alias HexpmWeb.MDExPlugins.InlineAttributeLists

  # Placeholder that will be replaced with the actual nonce at runtime
  @nonce_placeholder "%%SCRIPT_NONCE%%"

  @header_tags [3, 4]

  def compile(path, _name) do
    html =
      path
      |> File.read!()
      |> then(&MDEx.new(markdown: &1, syntax_highlight: [formatter: :html_linked]))
      |> MDExGFM.attach()
      |> MDEx.Document.run()
      |> MDEx.traverse_and_update(&InlineAttributeLists.transform/1)
      |> MDEx.traverse_and_update(&transform_node/1)
      |> MDEx.to_html!()

    # Generate code that replaces placeholder with actual nonce at runtime
    quote do
      nonce = var!(assigns)[:script_src_nonce] || ""

      unquote(html)
      |> String.replace(unquote(@nonce_placeholder), nonce)
      |> Phoenix.HTML.raw()
    end
  end

  defp transform_node(%MDEx.Heading{level: level, nodes: children} = node)
       when level in @header_tags do
    anchor =
      children
      |> extract_text()
      |> String.downcase()
      |> String.replace(" ", "-")
      |> String.replace(~r/[^a-zA-Z0-9\-]/, "")

    icon_html =
      HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
      |> Phoenix.HTML.safe_to_string()

    inner_html =
      %{node | nodes: children}
      |> MDEx.to_html!()
      |> String.trim()
      |> String.replace(~r/\A<h#{level}>(.*)<\/h#{level}>\z/s, "\\1")

    link_html = ~s|<a href="##{anchor}" class="hover-link">#{icon_html}</a> |

    %MDEx.HtmlBlock{
      literal:
        ~s|<h#{level} id="#{anchor}" class="section-heading">#{link_html}#{inner_html}</h#{level}>\n|
    }
  end

  defp transform_node(%MDEx.HtmlBlock{literal: literal} = node) do
    if String.contains?(literal, "<script") and
         not String.contains?(literal, ~s|nonce="#{@nonce_placeholder}"|) do
      updated = String.replace(literal, "<script", ~s|<script nonce="#{@nonce_placeholder}"|)
      %{node | literal: updated}
    else
      node
    end
  end

  defp transform_node(node), do: node

  defp extract_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &extract_text/1)
  defp extract_text(%{nodes: children}), do: extract_text(children)
  defp extract_text(%MDEx.Text{literal: text}), do: text
  defp extract_text(%MDEx.Code{literal: text}), do: text
  defp extract_text(_), do: ""
end
