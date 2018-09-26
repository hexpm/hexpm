defmodule Hexpm.Web.API.PackageDownloadController do
  use Hexpm.Web, :controller

  plug :maybe_fetch_package when action in [:show]

  plug :maybe_authorize,
       [domain: "api", resource: "read", fun: &maybe_organization_access/2]
       when action in [:index]

  plug :maybe_authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:show]

  def show(conn, _params) do
    if package = conn.assigns.package do
      when_stale(conn, package, fn conn ->
        package = Packages.preload(package)
        owners = Enum.map(Owners.all(package, user: :emails), & &1.user)
        package = %{package | owners: owners}

        conn
        |> api_cache(:public)
        |> render(:show, package_download: package)
      end)
    else
      not_found(conn)
    end
  end
end
