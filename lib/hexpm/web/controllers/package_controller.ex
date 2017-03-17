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

    sort          = Hexpm.Utils.safe_to_atom(params["sort"] || "name", @sort_params)
    page_param    = Hexpm.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(filter)
    page          = Hexpm.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages      = fetch_packages(page, @packages_per_page, filter, sort)
    exact_match   = Packages.get(params["repository"], search || "")

    render conn, "index.html", [
      title:         "Packages",
      container:     "container",
      per_page:      @packages_per_page,
      search:        search,
      letter:        letter,
      sort:          sort,
      package_count: package_count,
      page:          page,
      packages:      packages,
      letters:       @letters,
      downloads:     Packages.packages_downloads(packages, "all"),
      exact_match:   exact_match
    ]
  end

  def show(conn, params) do
    if package = Packages.get(params["repository"], params["name"]) do
      releases = Releases.all(package)

      {release, type} =
        if version = params["version"] do
          {matching_release(releases, version), :release}
        else
          {Release.latest_version(releases, only_stable: true, unstable_fallback: true), :package}
        end

      if release do
        package(conn, package, releases, release, type)
      end
    end || not_found(conn)
  end

  defp matching_release(releases, version) do
    Enum.find(releases, &(to_string(&1.version) == version))
  end

  defp package(conn, package, releases, release, type) do
    release = Releases.preload(release)

    docs_assigns =
      cond do
        type == :package and Enum.any?(releases, &(&1.has_docs)) ->
          [hexdocs_url: Hexpm.Utils.docs_url([package.name]),
           docs_tarball_url: Hexpm.Utils.docs_tarball_url(package, release)]
        type == :release and release.has_docs ->
          [hexdocs_url: Hexpm.Utils.docs_url(package, release),
           docs_tarball_url: Hexpm.Utils.docs_tarball_url(package, release)]
        true ->
          [hexdocs_url: nil, docs_tarball_url: nil]
      end

    downloads = Packages.package_downloads(package)
    owners = Owners.all(package) |> Users.with_emails

    render conn, "show.html", [
      title:             package.name,
      description:       package.meta.description,
      container:         "container package-view",
      canonical_url:     package_url(conn, :show, package),
      package:           package,
      releases:          releases,
      current_release:   release,
      downloads:         downloads,
      owners:            owners
    ] ++ docs_assigns
  end

  defp fetch_packages(page, packages_per_page, search, sort) do
    packages = Packages.search(page, packages_per_page, search, sort)
    Packages.attach_versions(packages)
  end
end
