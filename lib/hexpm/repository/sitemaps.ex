defmodule Hexpm.Repository.Sitemaps do
  use Hexpm.Context
  require EEx

  docs_template = ~S"""
  <?xml version="1.0" encoding="utf-8"?>
  <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <%= for {name, docs_updated_at} <- packages do %>
    <sitemap>
      <loc><%= Hexpm.Utils.docs_html_apex_url(name) <> "sitemap.xml" %></loc><%= if docs_updated_at do %>
      <lastmod><%= Hexpm.Utils.binarify(docs_updated_at) %></lastmod><% end %>
    </sitemap>
  <% end %>
  </sitemapindex>
  """

  EEx.function_from_string(:def, :render_docs, docs_template, [:packages])

  def packages() do
    from(
      p in Package,
      where: p.repository_id == 1,
      order_by: p.name,
      select: {p.name, p.updated_at}
    )
    |> Repo.all()
  end

  def packages_with_docs() do
    packages =
      from(
        p in Package,
        as: :package,
        order_by: p.name,
        where: p.repository_id == 1,
        where: not is_nil(p.docs_updated_at),
        where:
          exists(
            from(r in Release,
              where: r.package_id == parent_as(:package).id,
              where: r.has_docs,
              select: 1
            )
          ),
        select: {p.name, p.docs_updated_at}
      )
      |> Repo.all()

    [{"elixir", nil}, {"hex", nil} | packages]
  end

  def packages_for_preview() do
    releases_query = from(Release, select: [:version, :retirement])

    query =
      from(Package,
        order_by: :name,
        where: [repository_id: 1],
        select: [:id, :name, :updated_at],
        preload: [releases: ^releases_query]
      )

    for package <- Repo.all(query) do
      version = Release.latest_version(package.releases, only_stable: false).version
      {package.name, version, package.updated_at}
    end
  end
end
