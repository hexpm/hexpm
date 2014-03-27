defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Plug
  alias HexWeb.Web.Templates
  alias HexWeb.Stats.PackageDownload
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
    render(conn, :index)
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
    render(conn, :packages)
  end

  def safe_page(page, _count) when page < 1,
    do: 1
  def safe_page(page, count) when page > div(count, @packages) + 1,
    do: div(count, @packages) + 1
  def safe_page(page, _count),
    do: page

  match _ do
    send_resp(conn, 404, "404 FAIL")
  end

  defp render(conn, page) do
    { :safe, body } = Templates.render(page, conn.assigns)
    send_resp(conn, 200, body)
  end
end
