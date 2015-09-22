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
  alias HexWeb.Util


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
    title     = "Mix Usage"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_usage")
  end

  get "docs/rebar3_usage" do
    active    = :docs
    title     = "Rebar3 Usage"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_rebar3_usage")
  end

  get "docs/publish" do
    active    = :docs
    title     = "Mix Publish package"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_publish")
  end

  get "docs/rebar3_publish" do
    active    = :docs
    title     = "Rebar3 Publish package"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_rebar3_publish")
  end

  get "docs/tasks" do
    active    = :docs
    title     = "Mix tasks"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_tasks")
  end

  get "docs/codeofconduct" do
    active    = :docs
    title     = "Code of Conduct"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_codeofconduct")
  end

  get "docs/faq" do
    active    = :docs
    title     = "FAQ"

    conn = assign_pun(conn, [active, title])
    send_page(conn, :"docs_faq")
  end

  get "/packages" do
    active        = :packages
    title         = "Packages"
    conn          = fetch_params(conn)
    per_page      = @packages
    search        = conn.params["search"] |> Util.safe_search
    sort          = Util.safe_to_atom(conn.params["sort"] || "name", ~w(name downloads inserted_at))
    package_count = Package.count(search)
    page          = Util.safe_page(Util.safe_int(conn.params["page"]) || 1, package_count, @packages)
    packages      = fetch_packages(page, @packages, search, sort)
    downloads     = PackageDownload.packages(packages, "all")

    conn = assign_pun(conn, [search, page, packages, downloads, package_count, active,
                             title, per_page, sort])
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
      mix_snippet = Util.mix_snippet_version(current_release.version)
      rebar_snippet = Util.rebar_snippet_version(current_release.version)
    end

    conn = assign_pun(conn, [package, releases, current_release, downloads,
                             release_downloads, active, title, mix_snippet, rebar_snippet])
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

  def send_page(conn, page) do
    body = Templates.render(page, conn.assigns)
    status = conn.assigns[:status] || 200

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(status, body)
  end
end
