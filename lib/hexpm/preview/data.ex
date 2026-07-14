defmodule Hexpm.Preview.Data do
  import Ecto.Query

  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, Release}

  def release_exists?(package, version) do
    from(r in Release,
      join: p in Package,
      on: p.id == r.package_id,
      where: p.repository_id == 1 and p.name == ^package and r.version == ^version,
      select: true
    )
    |> Repo.exists?()
  end

  def latest_version(package) do
    from(r in Release,
      join: p in Package,
      on: p.id == r.package_id,
      where: p.repository_id == 1 and p.name == ^package
    )
    |> Repo.all()
    |> Release.latest_version(only_stable: true, unstable_fallback: true)
    |> case do
      nil -> nil
      release -> release.version
    end
  end

  def packages do
    from(p in Package,
      where: p.repository_id == 1,
      order_by: p.name,
      select: {p.name, p.updated_at}
    )
    |> Repo.all()
  end
end
