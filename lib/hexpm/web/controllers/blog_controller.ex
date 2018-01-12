defmodule Hexpm.Web.BlogController do
  use Hexpm.Web, :controller

  Enum.each(Hexpm.Web.BlogView.all_templates(), fn {slug, template} ->
    defp slug_to_template(unquote(slug)), do: unquote(Path.rootname(template))
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
    if template = slug_to_template(slug) do
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
