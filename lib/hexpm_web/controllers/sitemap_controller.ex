defmodule HexpmWeb.SitemapController do
  use HexpmWeb, :controller

  def main(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> render("packages_sitemap.xml", packages: Sitemaps.packages())
  end

  def docs(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> render("docs_sitemap.xml", packages: Sitemaps.packages_with_docs())
  end

  def preview(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> render("preview_sitemap.xml", packages: Sitemaps.packages_for_preview())
  end
end
