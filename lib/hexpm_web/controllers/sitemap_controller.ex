defmodule HexpmWeb.SitemapController do
  use HexpmWeb, :controller

  alias Hexpm.Preview

  def main(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> render("packages_sitemap.xml", packages: Sitemaps.public_packages())
  end

  def docs(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, Sitemaps.render_docs(Sitemaps.packages_with_docs()))
  end

  def preview_index(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, Preview.index_sitemap(HexpmWeb.Endpoint.url()))
  end

  def preview_package(conn, %{"package" => package}) do
    case Preview.package_sitemap(HexpmWeb.Endpoint.url(), package) do
      {:ok, sitemap} ->
        conn
        |> put_resp_content_type("text/xml")
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, sitemap)

      :error ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
