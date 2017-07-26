defmodule Hexpm.Web.PackageController do
  use Hexpm.Web, :controller

  @packages_per_page 30
  @sort_params ~w(name downloads inserted_at updated_at)
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

    repositories = Users.all_repositories(conn.assigns.current_user)
    sort = Hexpm.Utils.safe_to_atom(params["sort"] || "name", @sort_params)
    page_param = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(repositories, filter)
    page = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages = fetch_packages(repositories, page, @packages_per_page, filter, sort)
    downloads = Packages.packages_downloads(packages, "all")
    exact_match = exact_match(repositories, search)

    render(conn, "index.html", [
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
    ])
  end

  def show(conn, params) do
    params = fixup_params(params)
    %{"repository" => repository, "name" => name} = params
    repositories = Users.all_repositories(conn.assigns.current_user)

    if repository in Enum.map(repositories, & &1.name) do
      if package = Packages.get(repository, name) do
        releases = Releases.all(package)

        {release, type} =
          if version = params["version"] do
            {matching_release(releases, version), :release}
          else
            {Release.latest_version(releases, only_stable: true, unstable_fallback: true), :package}
          end

        if release do
          package(conn, repositories, package, releases, release, type)
        end
      end
    end || not_found(conn)
  end

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package(conn, repositories, package, releases, release, type) do
    release = Releases.preload(release)
    latest_release_with_docs = Enum.find(releases, & &1.has_docs)

    docs_assigns =
      cond do
        type == :package && latest_release_with_docs ->
          [hexdocs_url: Hexpm.Utils.docs_url([package.name]),
           docs_tarball_url: Hexpm.Utils.docs_tarball_url(package, latest_release_with_docs)]
        type == :release and release.has_docs ->
          [hexdocs_url: Hexpm.Utils.docs_url(package, release),
           docs_tarball_url: Hexpm.Utils.docs_tarball_url(package, release)]
        true ->
          [hexdocs_url: nil, docs_tarball_url: nil]
      end

    downloads = Packages.package_downloads(package)
    owners = Owners.all(package, [:emails])
    dependants = Packages.search(repositories, 1, 20, "depends:#{package.name}", :downloads, [:name, :repository_id])
    dependants_count = Packages.count(repositories, "depends:#{package.name}")

    render(conn, "show.html", [
      title: package.name,
      description: package.meta.description,
      container: "container package-view",
      canonical_url: package_url(conn, :show, package),
      package: package,
      releases: releases,
      current_release: release,
      downloads: downloads,
      owners: owners,
      dependants: dependants,
      dependants_count: dependants_count
    ] ++ docs_assigns)
  end

  defp fetch_packages(repositories, page, packages_per_page, search, sort) do
    packages = Packages.search(repositories, page, packages_per_page, search, sort, nil)
    Packages.attach_versions(packages)
  end

  defp exact_match(_repositories, nil) do
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
