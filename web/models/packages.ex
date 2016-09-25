defmodule HexWeb.Packages do
  use HexWeb.Web, :crud

  def get(name) do
    Repo.get_by!(Package, name: name)
  end

  def preload(package) do
    package = Repo.preload(package, [
      :downloads,
      releases: from(r in Release, select: map(r, [:version, :inserted_at, :updated_at]))
    ])
    update_in(package.releases, &Release.sort/1)
  end

  def search(page, query, sort) do
    Package.all(page, 100, query, sort)
    |> Ecto.Query.preload(releases: ^from(r in Release, select: map(r, [:version])))
    |> Repo.all
    |> Enum.map(fn package ->
      update_in(package.releases, &Release.sort/1)
    end)
  end
end
