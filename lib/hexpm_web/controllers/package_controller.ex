defmodule HexpmWeb.PackageController do
  use HexpmWeb, :controller

  @packages_per_page 30
  @audit_logs_per_page 10
  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at recently_published total_dependants)
  @letters for letter <- ?A..?Z, do: <<letter>>

  def index(conn, params) do
    letter = Hexpm.Utils.parse_search(params["letter"])
    search = Hexpm.Utils.parse_search(params["search"])

    filter =
      cond do
        letter ->
          {:letter, letter}

        search ->
          search

        true ->
          nil
      end

    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Enum.map(organizations, & &1.repository)
    sort = sort(params["sort"])
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, filter)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages = fetch_packages(repositories, page, @packages_per_page, filter, sort)
    downloads = Packages.packages_downloads_with_all_views(packages)
    exact_match = exact_match(repositories, search)

    render(
      conn,
      "index.html",
      title: "Packages",
      container: "container",
      per_page: @packages_per_page,
      search: search,
      letter: letter,
      sort: sort,
      package_count: package_count,
      page: page,
      packages: packages,
      letters: @letters,
      downloads: downloads,
      exact_match: exact_match
    )
  end

  def show(conn, params) do
    # TODO: Show flash if private package and organization does not have active billing

    params = fixup_params(params)
    %{"repository" => repository, "name" => name} = params
    organizations = Users.all_organizations(conn.assigns.current_user)
    repositories = Map.new(organizations, &{&1.repository.name, &1.repository})

    if repository = repositories[repository] do
      package = repository && Packages.get(repository, name)

      # Should have access even though organization does not have active billing
      if package do
        releases = Releases.all(package)

        {release, type} =
          if version = params["version"] do
            {matching_release(releases, version), :release}
          else
            {Release.latest_version(releases, only_stable: true, unstable_fallback: true),
             :package}
          end

        if release do
          repositories = Enum.map(organizations, & &1.repository)
          package(conn, repositories, package, releases, release, type)
        end
      end
    end || not_found(conn)
  end

  defp sort(nil), do: sort("recent_downloads")
  defp sort("downloads"), do: sort("recent_downloads")
  defp sort(param), do: Hexpm.Utils.safe_to_atom(param, @sort_params)

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package(conn, repositories, package, releases, release, type) do
    repository = package.repository
    release = Releases.preload(release, [:requirements, :downloads, :publisher])
    latest_release_with_docs = Enum.find(releases, & &1.has_docs)

    docs_assigns =
      cond do
        type == :package && latest_release_with_docs ->
          [
            docs_html_url: Hexpm.Utils.docs_html_url(repository, package, nil),
            docs_tarball_url:
              Hexpm.Utils.docs_tarball_url(repository, package, latest_release_with_docs)
          ]

        type == :release and release.has_docs ->
          [
            docs_html_url: Hexpm.Utils.docs_html_url(repository, package, release),
            docs_tarball_url: Hexpm.Utils.docs_tarball_url(repository, package, release)
          ]

        true ->
          [docs_html_url: nil, docs_tarball_url: nil]
      end

    downloads = Packages.package_downloads(package)
    owners = Owners.all(package, user: [:emails, :organization])

    dependants =
      Packages.search(
        repositories,
        1,
        20,
        "depends:#{repository.name}:#{package.name}",
        :recent_downloads,
        [:name, :repository_id]
      )

    dependants_count = Packages.count(repositories, "depends:#{package.name}")

    audit_logs = AuditLogs.all_by(package, 1, @audit_logs_per_page)

    render(
      conn,
      "show.html",
      [
        title: package.name,
        description: package.meta.description,
        container: "container package-view",
        canonical_url: Routes.package_url(conn, :show, package),
        package: package,
        repository_name: repository.name,
        releases: releases,
        current_release: release,
        downloads: downloads,
        owners: owners,
        dependants: dependants,
        dependants_count: dependants_count,
        audit_logs: audit_logs
      ] ++ docs_assigns
    )
  end

  defp fetch_packages(repositories, page, packages_per_page, search, sort) do
    packages = Packages.search(repositories, page, packages_per_page, search, sort, nil)
    Packages.attach_versions(packages)
  end

  defp exact_match(_organizations, nil) do
    nil
  end

  defp exact_match(repositories, search) do
    case String.split(search, "/", parts: 2) do
      [repository, package] ->
        if repository in Enum.map(repositories, & &1.name) do
          Packages.get(repository, package)
        end

      _ ->
        try do
          Packages.get(repositories, search)
        rescue
          Ecto.MultipleResultsError ->
            nil
        end
    end
  end

  defp fixup_params(%{"name" => name, "version" => version} = params) do
    case Version.parse(version) do
      {:ok, _} ->
        params

      :error ->
        params
        |> Map.put("repository", name)
        |> Map.put("name", version)
        |> Map.delete("version")
    end
  end

  defp fixup_params(params) do
    params
  end
end
