defmodule HexpmWeb.BlogController do
  use HexpmWeb, :controller

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
    if post = HexpmWeb.BlogView.post(slug) do
      render(conn, "layout.html",
        view: post.template,
        title: title(slug),
        slug: slug,
        post: post,
        container: nil
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
