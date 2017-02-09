defmodule HexWeb.SitemapController do
  use HexWeb.Web, :controller

  def sitemap(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> render("packages_sitemap.xml", packages: Sitemaps.packages())
  end
end
