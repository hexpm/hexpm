defmodule Hexpm.Web.BlogController do
  use Hexpm.Web, :controller

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Blog",
      container: "container page blog"
    )
  end

  def show(conn, %{"name" => "private-packages-and-organizations"}) do
    redirect(conn, to: Routes.blog_path(Endpoint, :show, "001-private-packages-and-organizations"))
  end

  def show(conn, %{"name" => name}) do
    if name in all_slugs() do
      render(
        conn,
        "#{name}.html",
        title: title(name),
        container: "container page blog"
      )
    else
      not_found(conn)
    end
  end

  defp all_slugs() do
    Hexpm.Web.BlogView.all_templates()
    |> Enum.map(&Path.rootname/1)
  end

  defp title(slug) do
    slug
    |> String.replace("-", " ")
    |> String.capitalize()
  end
end
