defmodule Hexpm.Repository.Packages do
  use Hexpm.Context

  def count() do
    Repo.one!(Package.count())
  end

  def count(repositories, filter) do
    Repo.one!(Package.count(repositories, filter))
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
    |> Repo.preload([:repository, :security_vulnerability_disclosures])
  end

  def get(repository, name) do
    package = Repo.get_by(assoc(repository, :packages), name: name)

    package &&
      Repo.preload(%{package | repository: repository}, [:security_vulnerability_disclosures])
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

  @spec resolve_hexpm_package_ids(package_names :: [name]) :: %{optional(name) => pos_integer()}
        when name: String.t()
  def resolve_hexpm_package_ids(package_names) do
    from(package in Package,
      join: repository in assoc(package, :repository),
      where: repository.name == "hexpm" and package.name in ^package_names,
      select: {package.name, package.id}
    )
    |> Repo.all()
    |> Map.new()
  end
end
