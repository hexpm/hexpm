defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Plug
  alias HexWeb.Web.Templates
  alias HexWeb.Stats.PackageDownload
  alias HexWeb.Release
  alias HexWeb.Package


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

  match _ do
    send_resp(conn, 404, "404 FAIL")
  end

  defp render(conn, page) do
    { :safe, body } = Templates.render(page, conn.assigns)
    send_resp(conn, 200, body)
  end
end
