defmodule HexpmWeb.Readme.Renderer do
  @moduledoc """
  Renders README content to sanitized HTML.

  Parses the Floki tree once and passes it through the sanitizer and URL
  rewriter before serializing to HTML. This avoids re-parsing the HTML string
  multiple times, which would cause mochiweb to strip significant whitespace
  inside <pre> blocks.
  """

  alias HexpmWeb.MDExPlugins.HeadingAnchors
  alias HexpmWeb.MDExPlugins.InlineAttributeLists
  alias HexpmWeb.Readme.{Sanitizer, URLRewriter}

  @header_tags [1, 2, 3, 4, 5, 6]

  # Matches whitespace-only text between tags inside <pre> blocks.
  # Replaced with HTML entities before Floki parsing to work around
  # mochiweb stripping significant whitespace: https://github.com/philss/floki/issues/75
  @pre_whitespace_regex ~r/(<pre[\s\S]*?>[\s\S]*?<\/pre>)/i

  @doc """
  Converts README content to sanitized, URL-rewritten HTML.
  """
  def render(filename, content, package_name, version) do
    ext = Path.extname(filename) |> String.downcase()

    html =
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

        _ ->
          "<pre>#{Plug.HTML.html_escape(content)}</pre>"
      end

    html
    |> protect_pre_whitespace()
    |> Floki.parse_document!()
    |> Sanitizer.sanitize()
    |> URLRewriter.rewrite(package_name, version)
    |> Floki.raw_html()
  end

  defp protect_pre_whitespace(html) do
    Regex.replace(@pre_whitespace_regex, html, fn _full, pre ->
      String.replace(pre, ~r/(?<=>)\s+(?=<)/, fn ws ->
        ws
        |> String.replace(" ", "&#32;")
        |> String.replace("\n", "&#10;")
        |> String.replace("\t", "&#9;")
      end)
    end)
  end
end
