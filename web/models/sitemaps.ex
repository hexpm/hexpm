defmodule HexWeb.Sitemaps do
  use HexWeb.Web, :crud

  def publish_docs_sitemap do
    packages = Repo.all(Package.docs_sitemap)
    sitemap = HexWeb.SitemapView.render("docs_sitemap.xml", packages: packages)
    HexWeb.Assets.push_docs_sitemap(sitemap)
  end
end
