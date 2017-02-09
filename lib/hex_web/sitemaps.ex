defmodule HexWeb.Sitemaps do
  use HexWeb.Web, :crud

  def packages do
    from(p in Package,
         order_by: p.name,
         select: {p.name, p.updated_at})
    |> Repo.all
  end

  def packages_with_docs do
    from(p in Package,
         order_by: p.name,
         where: not is_nil(p.docs_updated_at),
         select: {p.name, p.docs_updated_at})
    |> Repo.all
  end

  def publish_docs_sitemap do
    sitemap = HexWeb.SitemapView.render("docs_sitemap.xml", packages: packages_with_docs())
    HexWeb.Assets.push_docs_sitemap(sitemap)
  end
end
