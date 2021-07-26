defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  def compile(path, _name) do
    html =
      path
      |> File.read!()
      |> Earmark.as_html!(%Earmark.Options{gfm: true})
      |> header_anchors("h3")
      |> header_anchors("h4")

    {:safe, html}
  end

  defp header_anchors(html, tag) do
    icon =
      HexpmWeb.ViewIcons.icon(:glyphicon, :link, class: "icon-link")
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
