defmodule Hexpm.Repository.Packages do
  use Hexpm.Context

  def count() do
    Repo.one!(Package.count())
  end

  def count(repositories, filter) do
    Repo.one!(Package.count(repositories, filter))
  end

  def count_dependants(repositories, dependency) do
    Repo.one!(Package.count_dependants(repositories, dependency))
  end

  def diff(packages, nil), do: packages

  def diff(packages, remove) do
    names = Enum.map(List.wrap(remove), & &1.name)

    packages
    |> Enum.reject(&(&1.name in names))
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

  def dependants(repositories, dependency, page, packages_per_page, sort, fields \\ nil) do
    if sort in [:recent_downloads, :total_downloads] do
      dependants_by_downloads(repositories, dependency, page, packages_per_page, sort, fields)
    else
      Package.dependants(repositories, dependency, page, packages_per_page, sort, fields)
      |> Repo.all()
      |> attach_repositories(repositories)
    end
  end

  def search_with_versions(repositories, page, packages_per_page, query, sort) do
    Package.all(repositories, page, packages_per_page, query, sort, nil)
    |> Ecto.Query.preload(
      releases:
        ^from(r in Release,
          select: struct(r, [:id, :version, :inserted_at, :updated_at, :has_docs, :retirement])
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

  defp dependants_by_downloads(repositories, dependency, page, packages_per_page, sort, fields) do
    view = dependant_download_view(sort)
    offset = (page - 1) * packages_per_page

    downloaded_ids =
      Package.downloaded_dependant_ids(
        repositories,
        dependency,
        view,
        packages_per_page,
        offset
      )
      |> Repo.all()

    remaining = packages_per_page - length(downloaded_ids)

    package_ids =
      if remaining > 0 do
        downloaded_count =
          if downloaded_ids == [] and offset > 0 do
            Repo.one!(Package.count_downloaded_dependants(repositories, dependency, view))
          else
            offset + length(downloaded_ids)
          end

        zero_download_offset = max(offset - downloaded_count, 0)

        zero_download_ids =
          Package.undownloaded_dependant_ids(
            repositories,
            dependency,
            view,
            remaining,
            zero_download_offset
          )
          |> Repo.all()

        downloaded_ids ++ zero_download_ids
      else
        downloaded_ids
      end

    load_dependants(repositories, package_ids, fields)
  end

  defp load_dependants(_repositories, [], _fields), do: []

  defp load_dependants(repositories, package_ids, fields) do
    packages =
      package_ids
      |> Package.by_ids(fields)
      |> Repo.all()
      |> attach_repositories(repositories)

    packages_by_id = Map.new(packages, &{&1.id, &1})

    Enum.map(package_ids, &Map.fetch!(packages_by_id, &1))
  end

  defp dependant_download_view(:recent_downloads), do: "recent"
  defp dependant_download_view(:total_downloads), do: "all"

  def recent(repository, count) do
    Repo.all(Package.recent(repository, count))
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
end
