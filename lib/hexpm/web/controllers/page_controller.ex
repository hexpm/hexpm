defmodule Hexpm.Web.PageController do
  use Hexpm.Web, :controller

  def index(conn, _params) do
    hexpm = Repository.hexpm()

    render(conn, "index.html", [
      container: "",
      custom_flash: true,
      hide_search: true,
      num_packages: Packages.count(),
      num_releases: Releases.count(),
      package_top: Packages.top_downloads(hexpm, "all", 8),
      package_new: Packages.recent(hexpm, 10),
      releases_new: Releases.recent(hexpm, 10),
      total: Packages.total_downloads()
    ])
  end

  def sponsors(conn, _params) do
    render(conn, "sponsors.html", [
      title: "Sponsors",
      container: "container page sponsors"
    ])
  end

  def letsencrypt(conn, %{"id" => id}) do
    if key = System.get_env("HEX_LETSENCRYPT") do
      [verify_id, _secret] = String.split(key, ".")

      if id == verify_id do
        conn
        |> put_layout(false)
        |> send_resp(200, key)
      end
    end || render_error(conn, 404)
  end
end
