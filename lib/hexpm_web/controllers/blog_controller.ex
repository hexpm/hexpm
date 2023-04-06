defmodule HexpmWeb.BlogController do
  use HexpmWeb, :controller

  Enum.each(HexpmWeb.Blog.Posts.all_templates(), fn {slug, template} ->
    defp slug_to_template(unquote(slug)), do: unquote(Path.rootname(template))
  end)

  defp slug_to_template(_other), do: nil

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      title: "Blog",
      container: "container page page-sm blog"
    )
  end

  def show(conn, %{"slug" => "002-organizations-going-live"}) do
    redirect(conn, to: ~p"/blog/organizations-going-live")
  end

  def show(conn, %{"slug" => "hex-v0.18-released"}) do
    redirect(conn, to: ~p"/blog/hex-v018-released")
  end

  def show(conn, %{"slug" => "hex-v0.19-released"}) do
    redirect(conn, to: ~p"/blog/hex-v019-released")
  end

  def show(conn, %{"slug" => "hex-v0.20-released"}) do
    redirect(conn, to: ~p"/blog/hex-v020-released")
  end

  def show(conn, %{"slug" => "hex-v0.21-released"}) do
    redirect(conn, to: ~p"/blog/hex-v021-released")
  end

  def show(conn, %{"slug" => "hex-v1.0-released-and-the-future-of-hex"}) do
    redirect(conn, to: ~p"/blog/hex-v10-released-and-the-future-of-hex")
  end

  def show(conn, %{"slug" => "hex-v2.0-released-with-new-version-solver"}) do
    redirect(conn, to: ~p"/blog/hex-v20-released-with-new-version-solver")
  end

  def show(conn, %{"slug" => slug}) do
    if template = slug_to_template(slug) do
      render(
        conn,
        "#{template}.html",
        title: title(slug),
        container: "container page page-sm blog"
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
