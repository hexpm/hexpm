defmodule HexpmWeb.API.RetirementController do
  use HexpmWeb, :controller

  plug :maybe_fetch_release when action in [:create, :delete]

  plug :authorize,
       [domain: "api", resource: "write", fun: &package_owner/2]
       when action in [:create, :delete]

  def create(conn, params) do
    package = conn.assigns.package

    if release = conn.assigns.release do
      case Releases.retire(package, release, params, audit: audit_data(conn)) do
        :ok ->
          conn
          |> api_cache(:private)
          |> send_resp(204, "")

        {:error, _, changeset, _} ->
          validation_failed(conn, changeset)
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, _params) do
    package = conn.assigns.package

    if release = conn.assigns.release do
      Releases.unretire(package, release, audit: audit_data(conn))

      conn
      |> api_cache(:private)
      |> send_resp(204, "")
    else
      not_found(conn)
    end
  end
end
