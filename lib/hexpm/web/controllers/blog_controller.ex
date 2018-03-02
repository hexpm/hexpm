defmodule Hexpm.Web.BlogController do
  use Hexpm.Web, :controller

  @skip_slugs ~w(002-organizations-going-live)

  Enum.each(Hexpm.Web.BlogView.all_templates(), fn {slug, template} ->
    unless slug in @skip_slugs do
      defp slug_to_template(unquote(slug)), do: unquote(Path.rootname(template))
    end
  end)

  defp slug_to_template(_other), do: nil

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Blog",
      container: "container page blog"
    )
  end

  def show(conn, %{"slug" => slug}) do
    template = slug_to_template(slug)

    if slug not in @skip_slugs && template do
      render(
        conn,
        "#{template}.html",
        title: title(slug),
        container: "container page blog"
      )
    else
      not_found(conn)
    end
  end

  defp title(slug) do
    slug
    |> String.replace("-", " ")
    |> String.capitalize()
  end
end
