defmodule HexWeb.SitemapController do
  use HexWeb.Web, :controller

  def sitemap(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> render("packages_sitemap.xml", packages: Sitemaps.packages())
  end
end
