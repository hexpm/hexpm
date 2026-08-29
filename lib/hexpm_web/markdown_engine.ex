defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  alias HexpmWeb.MDExPlugins.CodeCopy
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
      |> maybe_add_copy_controls(path)
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

  # Copy controls are docs-only. Blog and policy templates share this engine;
  # drop maybe_add_copy_controls/2 if those pages should get the same control.
  defp maybe_add_copy_controls(document, path) do
    if docs_template?(path) do
      {document, _index} = MDEx.traverse_and_update(document, 1, &CodeCopy.transform/2)
      document
    else
      document
    end
  end

  defp docs_template?(path) do
    path
    |> Path.split()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(&(&1 == ["templates", "docs"]))
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
