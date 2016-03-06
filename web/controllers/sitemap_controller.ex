defmodule HexWeb.SitemapController do
  use HexWeb.Web, :controller

  def sitemap(conn, _params) do
    packages = Package.packages_sitemap
               |> HexWeb.Repo.all
    conn
    |> put_resp_content_type("text/xml")
    |> render("packages_sitemap.xml", packages: packages)
  end
end
