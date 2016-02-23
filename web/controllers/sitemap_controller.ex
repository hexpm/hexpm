defmodule HexWeb.SitemapController do
  use HexWeb.Web, :controller

  def sitemap(conn, _params) do
    packages = HexWeb.Repo.all(Package)
    conn
    |> put_resp_content_type("text/xml")
    |> render("sitemap.xml", packages: packages)
  end
end
