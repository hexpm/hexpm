defmodule HexpmWeb.BlogView do
  use HexpmWeb, :view

  alias Hexpm.Utils

  def render("index.html", _assigns) do
    render_template("index.html", posts: posts())
  end

  def render("index.xml", _assigns) do
    render_template("index.xml", posts: posts())
  end

  def render(other, _assigns) do
    content_tag(:div, render_template(other, %{}), class: "show-post")
  end

  defp posts() do
    Enum.map(HexpmWeb.Blog.Posts.all_templates(), fn {slug, template} ->
      content = render(template, %{})
      content = Phoenix.HTML.safe_to_string(content)
      {published_rfc2822, published_human, author} = published_metadata(content)

      %{
        slug: slug,
        title: title(content),
        subtitle: subtitle(content),
        paragraph: first_paragraph(content),
        published: published_rfc2822,
        published_date: published_human,
        author: author
      }
    end)
  end

  defp first_paragraph(content) do
    regex_run(~r[<p>(.*)</p>]sU, content)
  end

  defp title(content) do
    regex_run(~r[<h2>(.*)</h2>]sU, content)
  end

  defp subtitle(content) do
    regex_run(~r[<div class="subtitle">(.*)</div>]sU, content)
  end

  defp published_metadata(content) do
    # Extract datetime from <time> tag
    iso_datetime =
      ~r[<time datetime="(.+)">(.+)</time>]sU
      |> regex_run(content)

    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(iso_datetime)

    # Extract author from subtitle - look for "by Author Name" pattern
    # The subtitle format is: <time>...</time> · by Author Name
    author =
      case Regex.run(~r/·\s*by\s+([^<]+)<\/div>/, content) do
        [_, name] -> String.trim(name)
        _ -> nil
      end

    {
      Utils.datetime_to_rfc2822(datetime),
      Calendar.strftime(datetime, "%d %b %Y"),
      author
    }
  end

  defp regex_run(regex, string) do
    regex
    |> Regex.run(string)
    |> Enum.at(1)
    |> String.trim()
  end
end
