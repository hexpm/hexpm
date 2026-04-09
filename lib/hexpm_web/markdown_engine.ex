defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  # Placeholder that will be replaced with the actual nonce at runtime
  @nonce_placeholder "%%SCRIPT_NONCE%%"

  @supported_languages %{
    "elixir" => Makeup.Lexers.ElixirLexer,
    "erlang" => Makeup.Lexers.ErlangLexer,
    "gleam" => Makeup.Lexers.GleamLexer
  }

  def compile(path, _name) do
    html =
      path
      |> File.read!()
      |> Earmark.as_html!(%Earmark.Options{gfm: true})
      |> header_anchors("h3")
      |> header_anchors("h4")
      |> highlight_code_blocks()
      |> replace_inline_alignment()
      |> inject_nonce_placeholder()

    # Generate code that replaces placeholder with actual nonce at runtime
    quote do
      nonce = var!(assigns)[:script_src_nonce] || ""

      unquote(html)
      |> String.replace(unquote(@nonce_placeholder), nonce)
      |> Phoenix.HTML.raw()
    end
  end

  # Replace <script> tags without nonce with placeholder nonce
  defp inject_nonce_placeholder(html) do
    String.replace(html, ~r/<script(?![^>]*nonce=)/, "<script nonce=\"#{@nonce_placeholder}\"")
  end

  defp header_anchors(html, tag) do
    icon =
      HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
      |> Phoenix.HTML.safe_to_string()

    Regex.replace(~r"<#{tag}>\n?(.*)<\/#{tag}>", html, fn _, header ->
      anchor =
        header
        |> String.downcase()
        |> dashify()
        |> only_alphanumeric()

      """
      <#{tag} id="#{anchor}" class="section-heading">
        <a href="##{anchor}" class="hover-link">
          #{icon}
        </a>
        #{header}
      </#{tag}>
      """
    end)
  end

  defp dashify(string) do
    String.replace(string, " ", "-")
  end

  defp only_alphanumeric(string) do
    String.replace(string, ~r"([^a-zA-Z0-9\-])", "")
  end

  # The markdown engine processes trusted internal .md files (not user READMEs),
  # so regex-based highlighting is appropriate here. Using Floki would normalize
  # SVG attributes (viewBox -> viewbox) breaking heroicon rendering.
  defp highlight_code_blocks(html) do
    Regex.replace(
      ~r{<pre><code class="([\w-]+)">(.*?)</code></pre>}s,
      html,
      fn full_match, lang, code ->
        language =
          if String.starts_with?(lang, "language-"),
            do: String.trim_leading(lang, "language-"),
            else: lang

        case Map.get(@supported_languages, language) do
          nil -> full_match
          lexer -> code |> unescape_html() |> Makeup.highlight(lexer: lexer)
        end
      end
    )
  end

  defp replace_inline_alignment(html) do
    Regex.replace(
      ~r/ style="text-align: (left|center|right);"/,
      html,
      fn _, align -> ~s( class="text-#{align}") end
    )
  end

  defp unescape_html(html) do
    html
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", ~s["])
  end
end
