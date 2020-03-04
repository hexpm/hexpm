defmodule HexpmWeb.BlogView do
  use HexpmWeb, :view

  alias Hexpm.Utils

  skip_slugs = ~w()

  all_templates =
    Phoenix.Template.find_all(@phoenix_root)
    |> Enum.map(&Phoenix.Template.template_path_to_name(&1, @phoenix_root))
    |> Enum.flat_map(fn
      <<n1, n2, n3, "-", slug::binary>> = template
      when n1 in ?0..?9 and n2 in ?0..?9 and n3 in ?0..?9 ->
        [{Path.rootname(slug), template}]

      _other ->
        []
    end)
    |> Enum.reject(fn {slug, _template} -> slug in skip_slugs end)
    |> Enum.sort_by(&elem(&1, 1), &>=/2)

  def render("index.html", _assigns) do
    render_template("index.html", posts: posts())
  end

  def render("index.xml", _assigns) do
    render_template("index.xml", posts: posts())
  end

  def render(other, _assigns) do
    content_tag(:div, render_template(other, %{}), class: "show-post")
  end

  def all_templates() do
    unquote(all_templates)
  end

  defp posts() do
    Enum.map(all_templates(), fn {slug, template} ->
      content = render(template, %{})
      content = Phoenix.HTML.safe_to_string(content)

      %{
        slug: slug,
        title: title(content),
        subtitle: subtitle(content),
        paragraph: first_paragraph(content),
        published: published(content)
      }
    end)
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

  defp published(content) do
    {:ok, datetime, _utc_offset} =
      ~r[<time datetime="(.+)">(.+)</time>]
      |> Regex.run(content)
      |> Enum.at(1)
      |> DateTime.from_iso8601()

    Utils.datetime_to_rfc2822(datetime)
  end
end
