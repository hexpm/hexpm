defmodule HexWeb.API.PackageController do
  use HexWeb.Web, :controller
  import Ecto.Query, only: [from: 2, preload: 2]

  @sort_params ~w(name downloads inserted_at updated_at)

  def index(conn, params) do
    page     = HexWeb.Utils.safe_int(params["page"])
    search   = HexWeb.Utils.parse_search(params["search"])
    sort     = HexWeb.Utils.safe_to_atom(params["sort"] || "name", @sort_params)

    packages =
      Package.all(page, 100, search, sort)
      |> preload(releases: ^from(r in Release, select: map(r, [:version])))
      |> HexWeb.Repo.all

    when_stale(conn, packages, [modified: false], fn conn ->
      packages = Enum.map packages, fn(package) ->
        update_in(package.releases, &Release.sort/1)
      end

      conn
      |> api_cache(:public)
      |> render(:index, packages: packages)
    end)
  end

  def show(conn, %{"name" => name}) do
    package = HexWeb.Repo.get_by!(Package, name: name)

    when_stale(conn, package, fn conn ->
      package = HexWeb.Repo.preload(package, [
        :downloads,
        releases: from(r in Release, select: map(r, [:version, :inserted_at, :updated_at]))
      ])
      package = update_in(package.releases, &Release.sort/1)

      conn
      |> api_cache(:public)
      |> render(:show, package: package)
    end)
  end
end
