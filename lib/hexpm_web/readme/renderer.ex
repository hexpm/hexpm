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
  alias HexpmWeb.SyntaxHighlight

  @header_tags [1, 2, 3, 4, 5, 6]

  @doc """
  Converts README content to sanitized, URL-rewritten HTML.
  """
  def render(
        repository,
        filename,
        content,
        package_name,
        version,
        syntax_highlight_budget \\ SyntaxHighlight.budget(),
        markdown_budget \\ [parse_time: 1_000]
      ) do
    ext = Path.extname(filename) |> String.downcase()
    content = scrub_invalid_utf8(content)

    tree =
      case ext do
        ext when ext in [".md", ".markdown"] ->
          markdown_tree(content, package_name, version, syntax_highlight_budget, markdown_budget)

        _ ->
          plain_tree(content)
      end

    tree
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(repository, package_name, version)
    |> LazyHTML.Tree.postwalk(&preserve_pre_newline/1)
    |> LazyHTML.Tree.to_html()
  end

  defp markdown_tree(content, package_name, version, syntax_highlight_budget, markdown_budget) do
    document =
      MDEx.new(
        markdown: content,
        budget: markdown_budget,
        extension: [description_lists: true, superscript: true, subscript: true]
      )
      |> MDExGFM.attach()
      |> MDEx.Document.run()

    case document do
      %MDEx.Document{} = document ->
        document
        |> MDEx.traverse_and_update(
          &highlight_code_block(&1, "readme #{package_name} #{version}", syntax_highlight_budget)
        )
        |> MDEx.traverse_and_update(&InlineAttributeLists.transform/1)
        |> MDEx.traverse_and_update(
          HeadingAnchors.transform(levels: @header_tags, hover_link: false)
        )
        |> MDEx.to_html!()
        |> InlineAttributeLists.apply_classes()
        |> HeadingAnchors.anchor()
        |> LazyHTML.from_fragment()
        |> LazyHTML.to_tree()

      _ ->
        plain_tree(content)
    end
  end

  defp plain_tree(content), do: [{"pre", [{"class", "plain-text"}], [content]}]

  defp highlight_code_block(
         %MDEx.CodeBlock{info: info, literal: literal},
         label,
         syntax_highlight_budget
       ) do
    language = info |> String.split() |> List.first("plaintext")

    html =
      SyntaxHighlight.highlight(literal, language, "#{label} #{language}",
        budget: syntax_highlight_budget
      )

    %MDEx.HtmlBlock{literal: html}
  end

  defp highlight_code_block(node, _label, _syntax_highlight_budget), do: node

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
