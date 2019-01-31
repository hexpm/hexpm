defmodule HexpmWeb.PageController do
  use HexpmWeb, :controller

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
      package_top: Packages.top_downloads(hexpm, "recent", 8),
      package_new: Packages.recent(hexpm, 10),
      releases_new: Releases.recent(hexpm, 10),
      total: Packages.total_downloads()
    )
  end

  def about(conn, _params) do
    render(
      conn,
      "about.html",
      title: "About Hex",
      container: "container page page-sm"
    )
  end

  def pricing(conn, _params) do
    render(
      conn,
      "pricing.html",
      title: "Pricing",
      container: "container page pricing"
    )
  end

  def sponsors(conn, _params) do
    render(
      conn,
      "sponsors.html",
      title: "Sponsors",
      container: "container page page-sm sponsors"
    )
  end
end
