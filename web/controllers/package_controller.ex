defmodule HexWeb.PackageController do
  use HexWeb.Web, :controller

  @packages_per_page 30
  @sort_params ~w(name downloads inserted_at)

  def index(conn, params) do
    search        = HexWeb.Utils.safe_search(params["search"])
    sort          = HexWeb.Utils.safe_to_atom(params["sort"] || "name", @sort_params)
    package_count = Package.count(search) |> HexWeb.Repo.one!
    page_param    = HexWeb.Utils.safe_int(params["page"]) || 1
    page          = HexWeb.Utils.safe_page(page_param, package_count, @packages_per_page)
    packages      = fetch_packages(page, @packages_per_page, search, sort)

    render conn, "index.html", [
      active:        :packages,
      title:         "Packages",
      per_page:      @packages_per_page,
      search:        search,
      sort:          sort,
      package_count: package_count,
      page:          page,
      packages:      packages,
      downloads:     PackageDownload.packages(packages, "all")
                     |> HexWeb.Repo.all
                     |> Enum.into(%{})
    ]
  end

  def show(conn, params) do
    if package = HexWeb.Repo.get_by(Package, name: params["name"]) do
      releases = Release.all(package)
                 |> HexWeb.Repo.all
                 |> Release.sort

      release =
        if version = params["version"] do
          Enum.find(releases, &(to_string(&1.version) == version))
        else
          List.first(releases)
        end

      if release do
        package(conn, package, releases, release)
      end
    end || not_found(conn)
  end

  defp package(conn, package, releases, release) do
    has_docs = Enum.any?(releases, fn(release) -> release.has_docs end)
    release = HexWeb.Repo.preload(release, requirements: Release.requirements(release))

    docs_assigns =
      if has_docs do
        [hexdocs_url: HexWeb.Utils.docs_url([package.name]),
         docs_tarball_url: HexWeb.Utils.docs_tarball_url(package, release)]
      else
        [hexdocs_url: nil, docs_tarball_url: nil]
      end

    render conn, "show.html", [
      active:            :packages,
      title:             package.name,
      description:       package.meta.description,
      canonical_url:     package_url(conn, :show, package),
      package:           package,
      releases:          releases,
      current_release:   release,
      downloads:         PackageDownload.package(package)
                         |> HexWeb.Repo.all
                         |> Enum.into(%{}),
      release_downloads: ReleaseDownload.release(release)
                         |> HexWeb.Repo.one
    ] ++ docs_assigns
  end

  # TODO: Clean up
  defp fetch_packages(page, packages_per_page, search, sort) do
    packages = Package.all(page, packages_per_page, search, sort)
               |> HexWeb.Repo.all
    versions = Release.package_versions(packages)
               |> HexWeb.Repo.all
               |> Enum.into(%{})

    Enum.map(packages, fn package ->
      version = Release.latest_version(versions[package.id])
      Map.put(package, :latest_version, version)
    end)
  end
end
