defmodule HexWeb.PackageController do
  use HexWeb.Web, :controller

  @packages_per_page 30
  @sort_params ~w(name downloads inserted_at updated_at)
  @letters for letter <- ?A..?Z, do: <<letter>>

  def index(conn, params) do
    letter = HexWeb.Utils.parse_search(params["letter"])
    search = HexWeb.Utils.parse_search(params["search"])

    filter =
      cond do
        letter ->
          {:letter, letter}
        search ->
          search
        true ->
          nil
      end

    sort          = HexWeb.Utils.safe_to_atom(params["sort"] || "name", @sort_params)
    page_param    = HexWeb.Utils.safe_int(params["page"]) || 1
    package_count = Packages.count(filter)
    page          = HexWeb.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages      = fetch_packages(page, @packages_per_page, filter, sort)

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
      downloads:     Packages.packages_downloads(packages, "all")
    ]
  end

  def show(conn, params) do
    if package = Packages.get(params["name"]) do
      releases = Releases.all(package)

      {release, type} =
        if version = params["version"] do
          {Enum.find(releases, &(to_string(&1.version) == version)), :release}
        else
          {List.first(releases), :package}
        end

      if release do
        package(conn, package, releases, release, type)
      end
    end || not_found(conn)
  end

  defp package(conn, package, releases, release, type) do
    release = Releases.preload(release)

    docs_assigns =
      cond do
        type == :package and Enum.any?(releases, fn(release) -> release.has_docs end) ->
          [hexdocs_url: HexWeb.Utils.docs_url([package.name]),
           docs_tarball_url: HexWeb.Utils.docs_tarball_url(package, release)]
        type == :release and release.has_docs ->
          [hexdocs_url: HexWeb.Utils.docs_url(package, release),
           docs_tarball_url: HexWeb.Utils.docs_tarball_url(package, release)]
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
