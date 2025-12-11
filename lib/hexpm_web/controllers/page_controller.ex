defmodule HexpmWeb.PageController do
  use HexpmWeb, :controller

  def index(conn, _params) do
    hexpm = Repository.hexpm()

    package_new =
      hexpm
      |> Packages.recent(6)
      |> process_new_packages()

    render(
      conn,
      "index.html",
      container: "",
      num_packages: Packages.count(),
      num_releases: Releases.count(),
      package_top: Downloads.top_packages(hexpm, "recent", 6),
      package_new: package_new,
      releases_new: Releases.recent(hexpm, 6),
      total: Downloads.total()
    )
  end

  defp process_new_packages(results) do
    packages =
      results
      |> Enum.map(fn {name, inserted_at, meta, downloads} ->
        %Hexpm.Repository.Package{
          name: name,
          inserted_at: inserted_at,
          meta: meta,
          downloads: downloads
        }
      end)
      |> Packages.attach_latest_releases()

    Enum.zip_with(packages, results, fn package, {_name, inserted_at, meta, downloads} ->
      version = if package.latest_release, do: package.latest_release.version, else: nil
      {package.name, inserted_at, meta, version, downloads}
    end)
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
