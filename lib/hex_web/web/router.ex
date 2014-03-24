defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Connection
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

    config = HashDict.new(
      num_packages: num_packages,
      num_releases: num_releases,
      package_top: package_top,
      total: total)

    body = Templates.render(:index, config)
    send_resp(conn, 200, body)
  end

  match _ do
    send_resp(conn, 404, "404 FAIL")
  end
end
