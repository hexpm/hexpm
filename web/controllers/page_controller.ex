defmodule HexWeb.PageController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      num_packages: Package.count,
      num_releases: Release.count,
      package_top:  PackageDownload.top(:all, 10),
      package_new:  Package.recent(10),
      releases_new: Release.recent(10),
      total:        PackageDownload.total
    ]
  end
end
