defmodule HexpmWeb.Readme.Renderer do
  @moduledoc """
  Renders README content to sanitized HTML.

  Parses Markdown HTML with LazyHTML or builds a tree containing plain text.
  Passes the tree through the sanitizer and URL rewriter before serializing
  with LazyHTML, preserving whitespace and escaping text.
  """

  alias HexpmWeb.MDExPlugins.HeadingAnchors
  alias HexpmWeb.MDExPlugins.InlineAttributeLists
  alias HexpmWeb.Readme.{Sanitizer, URLRewriter}

  @header_tags [1, 2, 3, 4, 5, 6]

  @doc """
  Converts README content to sanitized, URL-rewritten HTML.
  """
  def render(repository, filename, content, package_name, version) do
    ext = Path.extname(filename) |> String.downcase()
    content = scrub_invalid_utf8(content)

    tree =
      case ext do
        ext when ext in [".md", ".markdown"] ->
          MDEx.new(
            markdown: content,
            extension: [description_lists: true, superscript: true, subscript: true],
            syntax_highlight: [formatter: :html_linked]
          )
          |> MDExGFM.attach()
          |> MDEx.Document.run()
          |> MDEx.traverse_and_update(&InlineAttributeLists.transform/1)
          |> MDEx.traverse_and_update(
            HeadingAnchors.transform(levels: @header_tags, hover_link: false)
          )
          |> MDEx.to_html!()
          |> LazyHTML.from_fragment()
          |> LazyHTML.to_tree()

        _ ->
          [{"pre", [], [content]}]
      end

    tree
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(repository, package_name, version)
    |> LazyHTML.Tree.postwalk(&preserve_pre_newline/1)
    |> LazyHTML.Tree.to_html()
  end

  # HTML parsing discards the first newline after <pre>. Prefix one so the
  # serialized HTML preserves the first text node when parsed again.
  defp preserve_pre_newline({"pre", attrs, [<<char, _::binary>> = text | children]})
       when char in [?\n, ?\r] do
    {"pre", attrs, ["\n" <> text | children]}
  end

  defp preserve_pre_newline(node), do: node

  # README files are extracted from package tarballs as raw bytes and may use
  # legacy encodings. MDEx's native parser raises on invalid UTF-8.
  defp scrub_invalid_utf8(content) do
    if String.valid?(content) do
      content
    else
      content
      |> String.chunk(:valid)
      |> Enum.map(fn chunk ->
        if String.valid?(chunk) do
          chunk
        else
          String.duplicate("�", byte_size(chunk))
        end
      end)
      |> IO.iodata_to_binary()
    end
  end
end
