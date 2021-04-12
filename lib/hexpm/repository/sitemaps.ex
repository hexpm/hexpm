defmodule Hexpm.Repository.Sitemaps do
  use Hexpm.Context

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
    from(
      p in Package,
      join: r in assoc(p, :releases),
      order_by: p.name,
      where: p.repository_id == 1,
      where: not is_nil(p.docs_updated_at),
      where: r.has_docs,
      select: {p.name, p.docs_updated_at},
      distinct: true
    )
    |> Repo.all()
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
