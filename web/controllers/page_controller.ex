defmodule HexWeb.PageController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      container:    "",
      custom_flash: true,
      hide_search:  true,
      num_packages: Packages.count,
      num_releases: Releases.count,
      package_top:  Packages.top_downloads("all", 8),
      package_new:  Packages.recent(10),
      releases_new: Releases.recent(10),
      total:        Packages.total_downloads
    ]
  end

  def sponsors(conn, _params) do
    render conn, "sponsors.html",
      title: "Sponsors",
      container: "container page sponsors"
  end
end
