defmodule HexpmWeb.BlogController do
  use HexpmWeb, :controller

  Enum.each(HexpmWeb.BlogView.all_templates(), fn {slug, template} ->
    defp slug_to_template(unquote(slug)), do: unquote(Path.rootname(template))
  end)

  defp slug_to_template(_other), do: nil

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Blog",
      container: "blog"
    )
  end

  def show(conn, %{"slug" => "002-organizations-going-live"}) do
    redirect(conn, to: Routes.blog_path(Endpoint, :show, "organizations-going-live"))
  end

  def show(conn, %{"slug" => slug}) do
    if template = slug_to_template(slug) do
      render_layout(conn, "#{template}.html", slug)
    else
      not_found(conn)
    end
  end

  defp render_layout(conn, view, slug) do
    render(conn, "layout.html", view: view, title: title(slug), slug: slug, container: nil)
  end

  defp title(slug) do
    slug
    |> String.replace("-", " ")
    |> String.capitalize()
  end
end
