defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  # Placeholder that will be replaced with the actual nonce at runtime
  @nonce_placeholder "%%SCRIPT_NONCE%%"

  def compile(path, _name) do
    html =
      path
      |> File.read!()
      |> Earmark.as_html!(%Earmark.Options{gfm: true})
      |> header_anchors("h3")
      |> header_anchors("h4")
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
end
