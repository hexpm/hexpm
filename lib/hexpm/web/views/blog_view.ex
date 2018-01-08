defmodule Hexpm.Web.BlogView do
  use Hexpm.Web, :view

  def render("index.html", _assigns) do
    posts =
      Enum.flat_map(all_templates(), fn
        "index.html" ->
          []

        name ->
          content = render(name, %{})
          content = Phoenix.HTML.safe_to_string(content)

          [
            %{
              slug: Path.rootname(name),
              title: title(content),
              subtitle: subtitle(content),
              paragraph: first_paragraph(content)
            }
          ]
      end)

    render_template("index.html", posts: posts)
  end

  def render(other, _assigns) do
    content_tag(:div, render_template(other, %{}), class: "show-post")
  end

  def all_templates() do
    Phoenix.Template.find_all(@phoenix_root)
    |> Enum.map(&Phoenix.Template.template_path_to_name(&1, @phoenix_root))
    |> Enum.sort()
    |> Enum.reverse()
  end

  defp first_paragraph(content) do
    ~r[<p>(.*)</p>]sU
    |> Regex.run(content)
    |> Enum.at(1)
  end

  defp title(content) do
    ~r[<h2>(.*)</h2>]
    |> Regex.run(content)
    |> Enum.at(1)
  end

  defp subtitle(content) do
    ~r[<div class="subtitle">(.*)</div>]
    |> Regex.run(content)
    |> Enum.at(1)
  end
end
