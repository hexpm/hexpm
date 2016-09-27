defmodule HexWeb.Packages do
  use HexWeb.Web, :crud

  def count(filter) do
     HexWeb.Repo.one!(Package.count(filter))
  end

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

  def search(page, packages_per_page, query, sort) do
    Package.all(page, packages_per_page, query, sort)
    |> Ecto.Query.preload(releases: ^from(r in Release, select: map(r, [:version])))
    |> Repo.all
    |> Enum.map(fn package ->
      update_in(package.releases, &Release.sort/1)
    end)
  end

  def package_downloads(package) do
    PackageDownload.package(package)
    |> Repo.all
    |> Enum.into(%{})
  end

  def packages_downloads(packages, view) do
    PackageDownload.packages(packages, view)
    |> Repo.all
    |> Enum.into(%{})
  end
end
