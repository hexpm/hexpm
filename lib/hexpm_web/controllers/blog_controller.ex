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
      container: "container page page-sm blog"
    )
  end

  def show(conn, %{"slug" => "002-organizations-going-live"}) do
    redirect(conn, to: Routes.blog_path(Endpoint, :show, "organizations-going-live"))
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
