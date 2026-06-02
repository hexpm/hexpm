defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  alias HexpmWeb.MDExPlugins.HeadingAnchors
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
      |> MDEx.traverse_and_update(HeadingAnchors.transform(levels: @header_tags))
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
end
