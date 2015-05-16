defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  alias HexWeb.Plug.NotFound
  alias HexWeb.Web.Templates
  alias HexWeb.Stats.PackageDownload
  alias HexWeb.Stats.ReleaseDownload
  alias HexWeb.Release
  alias HexWeb.Package
  alias HexWeb.User


  @packages 30

  plug Plug.Parsers, parsers: [:urlencoded, :multipart]
  plug :match
  plug :dispatch

  get "/" do
    num_packages = Package.count
    num_releases = Release.count
    releases_new = Release.recent(10)
    package_new  = Package.recent(10)
    package_top  = PackageDownload.top(:all, 10)
    total        = PackageDownload.total

    conn = assign_pun(conn, [num_packages, num_releases, package_top,
                             package_new, releases_new, total])
    send_page(conn, :index)
  end

  get "confirm" do
    conn = fetch_params(conn)
    name = conn.params["username"]
    key  = conn.params["key"]

    success = User.confirm?(name, key)

    conn = assign_pun(conn, [success])
    send_page(conn, :confirm)
  end

  get "reset" do
    conn = fetch_params(conn)

    name = conn.params["username"]
    key  = conn.params["key"]

    conn = assign_pun(conn, [name, key])
    send_page(conn, :reset)
  end

  post "reset" do
    name     = conn.params["username"]
    key      = conn.params["key"]
    password = conn.params["password"]

    success = User.reset?(name, key, password)

    conn = assign_pun(conn, [success])
    send_page(conn, :resetresult)
  end

  get "docs/usage" do
    active    = :docs
    title     = "Usage"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_usage")
  end

  get "docs/publish" do
    active    = :docs
    title     = "Publish package"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_publish")
  end

  get "docs/tasks" do
    active    = :docs
    title     = "Mix tasks"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_tasks")
  end

  get "codeofconduct" do
    active    = :docs
    title     = "Code of Conduct"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_codeofconduct")
  end

  get "/packages" do
    active            = :packages
    title             = "Packages"
    conn              = fetch_params(conn)
    packages_per_page = @packages
    search            = conn.params["search"] |> safe_query
    sort              = safe_sort(conn.params["sort"] || "name")

    package_count = Package.count(search)
    page          = safe_page(safe_int(conn.params["page"]) || 1, package_count)
    packages      = fetch_packages(page, packages_per_page, search, sort)
    downloads     = PackageDownload.packages(packages, "all")

    conn = assign_pun(conn, [search, page, packages, downloads, package_count, active,
                             title, packages_per_page, sort])
    send_page(conn, :packages)
  end

  get "/packages/:name" do
    if package = Package.get(name) do
      releases = Release.all(package)
      release = List.first(releases)

      package(conn, package, releases, release)
    else
      raise NotFound
    end
  end

  get "/packages/:name/:version" do
    if package = Package.get(name) do
      releases = Release.all(package)
      if release = Enum.find(releases, &(to_string(&1.version) == version)) do
        package(conn, package, releases, release)
      end
    end || raise NotFound
  end

  match _ do
    _conn = conn
    raise NotFound
  end

  defp package(conn, package, releases, current_release) do
    active    = :packages
    title     = package.name
    downloads = PackageDownload.package(package)

    if current_release do
      release_downloads = ReleaseDownload.release(current_release)
      reqs = Release.requirements(current_release)
      current_release = %{current_release | requirements: reqs}
    end

    conn = assign_pun(conn, [package, releases, current_release, downloads,
                             release_downloads, active, title])
    send_page(conn, :package)
  end

  defp fetch_packages(page, packages_per_page, search, sort) do
    packages = Package.all(page, packages_per_page, search, sort)
    latest_versions = Release.latest_versions(packages)

    Enum.map(packages, fn package ->
      version = latest_versions[package.id]
      Map.put(package, :latest_version, version)
    end)
  end

  defp safe_page(page, _count) when page < 1,
    do: 1
  defp safe_page(page, count) when page > div(count, @packages) + 1,
    do: div(count, @packages) + 1
  defp safe_page(page, _count),
    do: page

  defp safe_int(nil), do: nil

  defp safe_int(string) do
    case Integer.parse(string) do
      {int, ""} -> int
      _         -> nil
    end
  end

  defp safe_query(nil), do: nil

  defp safe_query(string) do
    string
    |> String.replace(~r/[^\w\s]/, "")
    |> String.strip
  end

  defp safe_sort("name") do
    :name
  end

  defp safe_sort("downloads") do
    :downloads
  end

  defp safe_sort(_), do: nil

  def send_page(conn, page) do
    body = Templates.render(page, conn.assigns)
    status = conn.assigns[:status] || 200

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(status, body)
  end
end
