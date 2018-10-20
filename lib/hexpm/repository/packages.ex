defmodule Hexpm.Repository.Packages do
  use HexpmWeb, :context

  def count() do
    Repo.one!(Package.count())
  end

  def count(organizations, filter) do
    Repo.one!(Package.count(organizations, filter))
  end

  def get(organization, name) when is_binary(organization) do
    organization = Organizations.get(organization)
    organization && get(organization, name)
  end

  def get(organizations, name) when is_list(organizations) do
    Repo.get_by(assoc(organizations, :packages), name: name)
    |> Repo.preload(:organization)
  end

  def get(organization, name) do
    package = Repo.get_by(assoc(organization, :packages), name: name)
    package && %{package | organization: organization}
  end

  def owner?(package, user) do
    Package.owner(package, user)
    |> Repo.one!()
  end

  def owner_with_access?(package, user) do
    organization = package.organization

    Repo.one!(Package.owner_with_access(package, user)) or
      (not organization.public and Organizations.access?(organization, user, "write"))
  end

  def owner_with_full_access?(package, user) do
    organization = package.organization

    Repo.one!(Package.owner_with_access(package, user, "full")) or
      (not organization.public and Organizations.access?(organization, user, "admin"))
  end

  def preload(package) do
    releases =
      from(
        r in Release,
        select:
          map(r, [
            :version,
            :inserted_at,
            :updated_at,
            :retirement,
            :has_docs
          ])
      )

    package =
      Repo.preload(package, [
        :downloads,
        releases: releases
      ])

    update_in(package.releases, &Release.sort/1)
  end

  def attach_versions(packages) do
    versions = Releases.package_versions(packages)

    Enum.map(packages, fn package ->
      version =
        Release.latest_version(versions[package.id], only_stable: true, unstable_fallback: true)

      %{package | latest_version: version}
    end)
  end

  def search(organizations, page, packages_per_page, query, sort, fields) do
    Package.all(organizations, page, packages_per_page, query, sort, fields)
    |> Repo.all()
    |> attach_organizations(organizations)
  end

  def search_with_versions(organizations, page, packages_per_page, query, sort) do
    Package.all(organizations, page, packages_per_page, query, sort, nil)
    |> Ecto.Query.preload(
      releases: ^from(r in Release, select: struct(r, [:id, :version, :updated_at]))
    )
    |> Repo.all()
    |> Enum.map(fn package -> update_in(package.releases, &Release.sort/1) end)
    |> attach_organizations(organizations)
  end

  defp attach_organizations(packages, organizations) do
    organizations = Map.new(organizations, &{&1.id, &1})

    Enum.map(packages, fn package ->
      organization = Map.fetch!(organizations, package.organization_id)
      %{package | organization: organization}
    end)
  end

  def recent(organization, count) do
    Repo.all(Package.recent(organization, count))
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

  def top_downloads(organization, view, count) do
    Repo.all(PackageDownload.top(organization, view, count))
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
    organizations = Users.all_organizations(for_user)
    organization_ids = Enum.map(organizations, & &1.id)

    # Atoms sort before strings
    sorter = fn org -> if(org.name == "hexpm", do: :first, else: org.name) end

    user.owned_packages
    |> Enum.filter(&(&1.organization_id in organization_ids))
    |> Enum.sort_by(&[sorter.(&1.organization), &1.name])
  end
end
