defmodule Hexpm.Web.PageController do
  use Hexpm.Web, :controller

  def index(conn, _params) do
    hexpm = Repository.hexpm()

    render(
      conn,
      "index.html",
      container: "",
      custom_flash: true,
      hide_search: true,
      num_packages: Packages.count(),
      num_releases: Releases.count(),
      package_top: Packages.top_downloads(hexpm, "all", 8),
      package_new: Packages.recent(hexpm, 10),
      releases_new: Releases.recent(hexpm, 10),
      total: Packages.total_downloads()
    )
  end

  def pricing(conn, _params) do
    render(conn, "pricing.html", [
      title: "Pricing",
      container: "container page pricing"
    ])
  end

  def sponsors(conn, _params) do
    render(
      conn,
      "sponsors.html",
      title: "Sponsors",
      container: "container page sponsors"
    )
  end
end
