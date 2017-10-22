defmodule Hexpm.Repository.Packages do
  use Hexpm.Web, :context

  def count() do
    Repo.one!(Package.count())
  end

  def count(repositories, filter) do
    Repo.one!(Package.count(repositories, filter))
  end

  def get(repository, name) when is_binary(repository) do
    repository = Repositories.get(repository)
    repository && get(repository, name)
  end

  def get(repositories, name) when is_list(repositories) do
    Repo.get_by(assoc(repositories, :packages), name: name)
    |> Repo.preload(:repository)
  end

  def get(repository, name) do
    package = Repo.get_by(assoc(repository, :packages), name: name)
    package && %{package | repository: repository}
  end

  def owner?(package, user) do
    Package.is_owner(package, user)
    |> Repo.one!()
  end

  def owner_with_access?(package, user) do
    repository = package.repository
    Repo.one!(Package.is_owner_with_access(package, user)) or
      (not repository.public and Repositories.access?(repository, user, "write"))
  end

  def preload(package) do
    releases = from(r in Release, select: map(r, [
      :version,
      :inserted_at,
      :updated_at,
      :retirement
    ]))

    package = Repo.preload(package, [
      :downloads,
      releases: releases
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

  def search(repositories, page, packages_per_page, query, sort, fields) do
    Package.all(repositories, page, packages_per_page, query, sort, fields)
    |> Repo.all()
    |> attach_repositories(repositories)
  end

  def search_with_versions(repositories, page, packages_per_page, query, sort) do
    Package.all(repositories, page, packages_per_page, query, sort, nil)
    |> Ecto.Query.preload(releases: ^from(r in Release, select: struct(r, [:id, :version, :updated_at])))
    |> Repo.all()
    |> Enum.map(fn package -> update_in(package.releases, &Release.sort/1) end)
    |> attach_repositories(repositories)
  end

  defp attach_repositories(packages, repositories) do
    repositories = Map.new(repositories, &{&1.id, &1})

    Enum.map(packages, fn package ->
      repository = Map.fetch!(repositories, package.repository_id)
      %{package | repository: repository}
    end)
  end

  def recent(repository, count) do
    Repo.all(Package.recent(repository, count))
  end

  def package_downloads(package) do
    PackageDownload.package(package)
    |> Repo.all()
    |> Enum.into(%{})
  end

  def packages_downloads_with_all_views(packages) do
    PackageDownload.packages_and_all_download_views(packages)
    |> Repo.all()
    |> Enum.reduce(%{}, fn({id, view, dls}, acc) ->
         Map.update(acc, id, %{view => dls}, &Map.put(&1, view, dls))
    end)
  end

  def packages_downloads(packages, view) do
    PackageDownload.packages(packages, view)
    |> Repo.all()
    |> Enum.into(%{})
  end

  def top_downloads(repository, view, count) do
    Repo.all(PackageDownload.top(repository, view, count))
  end

  def total_downloads() do
    PackageDownload.total()
    |> Repo.all()
    |> Enum.into(%{})
  end
end
