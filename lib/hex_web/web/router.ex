defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Plug
  alias HexWeb.Plug.NotFound
  alias HexWeb.Web.Templates
  alias HexWeb.Stats.PackageDownload
  alias HexWeb.Stats.ReleaseDownload
  alias HexWeb.Release
  alias HexWeb.Package


  @packages 30

  plug :match
  plug :dispatch

  get "/" do
    num_packages = Package.count
    num_releases = Release.count
    package_top  = PackageDownload.top(:all, 10)
    total        = PackageDownload.total

    conn = assign_pun(conn, [num_packages, num_releases, package_top, total])
    send_page(conn, :index)
  end

  get "/docs/usage" do
    active    = :docs
    title     = "Usage"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :docs_usage)
  end

  get "/docs/tasks" do
    active    = :docs
    title     = "Mix tasks"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :docs_tasks)
  end

  get "/packages" do
    conn      = fetch_params(conn)
    search    = conn.params["search"]
    pkg_count = Package.count(search)
    page      = safe_page(conn.params["page"] || 1, pkg_count)
    packages  = Package.all(page, @packages, search)
    active    = :packages
    title     = "Packages"

    conn = assign_pun(conn, [search, page, packages, pkg_count, active, title])
    send_page(conn, :packages)
  end

  get "/packages/:name" do
    if package = Package.get(name) do
      releases = Release.all(package)
      if release = List.first(releases) do
        release = release.requirements(Release.requirements(release))
      end

      package(conn, package, releases, release)
    else
      raise NotFound
    end
  end

  get "/packages/:name/:version" do
    if package = Package.get(name) do
      releases = Release.all(package)
      if release = Enum.find(releases, &(&1.version == version)) do
        package(conn, package, releases, release)
      end
    end || raise NotFound
  end

  match _ do
    raise NotFound
  end

  defp package(conn, package, releases, current_release) do
    active    = :packages
    title     = package.name
    downloads = PackageDownload.package(package)

    if current_release do
      release_downloads = ReleaseDownload.release(current_release)
    end

    conn = assign_pun(conn, [package, releases, current_release, downloads,
                             release_downloads, active, title])
    send_page(conn, :package)
  end

  defp safe_page(page, _count) when page < 1,
    do: 1
  defp safe_page(page, count) when page > div(count, @packages) + 1,
    do: div(count, @packages) + 1
  defp safe_page(page, _count),
    do: page

  def send_page(conn, page) do
    body = Templates.render(page, conn.assigns)

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, body)
  end
end
