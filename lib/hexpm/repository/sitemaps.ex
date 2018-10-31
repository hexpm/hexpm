defmodule Hexpm.Repository.Sitemaps do
  use HexpmWeb, :context

  def packages() do
    from(
      p in Package,
      where: p.organization_id == 1,
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
      where: p.organization_id == 1,
      where: not is_nil(p.docs_updated_at),
      where: r.has_docs,
      select: {p.name, p.docs_updated_at},
      distinct: true
    )
    |> Repo.all()
  end
end
