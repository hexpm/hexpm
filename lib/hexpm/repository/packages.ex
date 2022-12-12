defmodule Hexpm.Repository.Packages do
  use Hexpm.Context

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

  def owner_with_access?(package, user, level \\ "maintainer") do
    repository = package.repository
    role = PackageOwner.level_to_organization_role(level)

    Repo.one!(Package.package_owner(package, user, level)) or
      Repo.one!(Package.organization_owner(package, user, level)) or
      (repository.id != 1 and Organizations.access?(repository.organization, user, role))
  end

  def preload(package) do
    package = Repo.preload(package, [:downloads, :releases])
    update_in(package.releases, &Release.sort/1)
  end

  def attach_latest_releases(packages) do
    package_ids = Enum.map(packages, & &1.id)

    releases =
      from(
        r in Release,
        where: r.package_id in ^package_ids,
        group_by: r.package_id,
        select:
          {r.package_id,
           {fragment("array_agg(?)", r.version), fragment("array_agg(?)", r.inserted_at)}}
      )
      |> Repo.all()
      |> Map.new(fn {package_id, {versions, inserted_ats}} ->
        {package_id,
         Enum.zip_with(versions, inserted_ats, fn version, inserted_at ->
           %Release{version: version, inserted_at: inserted_at}
         end)}
      end)

    Enum.map(packages, fn package ->
      release =
        Release.latest_version(releases[package.id], only_stable: true, unstable_fallback: true)

      %{package | latest_release: release}
    end)
  end

  def search(repositories, page, packages_per_page, query, sort, fields) do
    Package.all(repositories, page, packages_per_page, query, sort, fields)
    |> Repo.all()
    |> attach_repositories(repositories)
  end

  def search_with_versions(repositories, page, packages_per_page, query, sort) do
    Package.all(repositories, page, packages_per_page, query, sort, nil)
    |> Ecto.Query.preload(
      releases:
        ^from(r in Release,
          select: struct(r, [:id, :version, :inserted_at, :updated_at, :has_docs])
        )
    )
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
    |> Enum.reduce(%{}, fn {id, view, dls}, acc ->
      Map.update(acc, id, %{view => dls}, &Map.put(&1, view, dls))
    end)
  end

  def packages_downloads(packages, view) do
    PackageDownload.packages(packages, view)
    |> Repo.all()
    |> Enum.into(%{})
  end

  def top_downloads(repository, view, count) do
    top = Repo.all(PackageDownload.top(repository, view, count))

    packages =
      top
      |> Enum.map(fn {package, _downloads} -> package end)
      |> attach_latest_releases()

    Enum.zip_with(packages, top, fn package, {_package, downloads} ->
      {package, downloads}
    end)
  end

  def total_downloads() do
    PackageDownload.total()
    |> Repo.all()
    |> Enum.into(%{})
  end

  def accessible_user_owned_packages(nil, _) do
    []
  end

  def accessible_user_owned_packages(user, for_user) do
    repositories = Enum.map(Users.all_organizations(for_user), & &1.repository)
    repository_ids = Enum.map(repositories, & &1.id)

    # Atoms sort before strings
    sorter = fn repo -> if(repo.id == 1, do: :first, else: repo.name) end

    user.owned_packages
    |> Enum.filter(&(&1.repository_id in repository_ids))
    |> Enum.sort_by(&[sorter.(&1.repository), &1.name])
  end

  def downloads_for_last_n_days(package_id, num_of_days) do
    Package.downloads_for_last_n_days(package_id, num_of_days)
    |> Repo.all()
  end
end
