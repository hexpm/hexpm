defmodule Hexpm.Repository.Packages do
  use Hexpm.Web, :context

  def count(filter \\ nil) do
    Repo.one!(Package.count(filter))
  end

  def get(repository, name) when is_binary(repository) do
    repository = Repositories.get(repository)
    repository && get(repository, name)
  end

  def get(repository, name) do
    package = Repo.get_by(assoc(repository, :packages), name: name)
    package && %{package | repository: repository}
  end

  def owner?(package, user) do
    Package.is_owner(package, user)
    |> Repo.one!
  end

  def preload(package) do
    package = Repo.preload(package, [
      :downloads,
      releases: from(r in Release, select: map(r, [:version, :inserted_at, :updated_at, :retirement]))
    ])
    update_in(package.releases, &Release.sort/1)
  end

  def attach_versions(packages) do
    versions = Releases.package_versions(packages)

    Enum.map(packages, fn package ->
      version = Release.latest_version(versions[package.id], only_stable: true, unstable_fallback: true)
      %{package | latest_version: version}
    end)
  end

  def search(page, packages_per_page, query, sort) do
    Package.all(page, packages_per_page, query, sort)
    |> Ecto.Query.preload(releases: ^from(r in Release, select: map(r, [:version])))
    |> Repo.all
    |> Enum.map(fn package ->
      update_in(package.releases, &Release.sort/1)
    end)
  end

  def recent(count) do
    Repo.all(Package.recent(count))
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

  def top_downloads(view, count) do
    Repo.all(PackageDownload.top(view, count))
  end

  def total_downloads do
    PackageDownload.total
    |> Repo.all
    |> Enum.into(%{})
  end
end
