defmodule HexWeb.PageController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      num_packages: Package.count
                    |> HexWeb.Repo.one!,
      num_releases: Release.count
                    |> HexWeb.Repo.one!,
      package_top:  PackageDownload.top("all", 10)
                    |> HexWeb.Repo.all,
      package_new:  Package.recent(10)
                    |> HexWeb.Repo.all,
      releases_new: Release.recent(10)
                    |> HexWeb.Repo.all,
      total:        PackageDownload.total
                    |> HexWeb.Repo.all
                    |> Enum.into(%{})
    ]
  end
end
