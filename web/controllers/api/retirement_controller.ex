defmodule HexWeb.API.RetirementController do
  use HexWeb.Web, :controller

  plug :fetch_release when action in [:create, :delete]
  plug :authorize, [fun: &package_owner?/2] when action in [:create, :delete]

  def create(conn, params) do
    package = conn.assigns.package
    release = conn.assigns.release

    case Releases.retire(package, release, params, audit: audit_data(conn)) do
      {:ok, _} ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, _, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  def delete(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release
    Releases.unretire(package, release, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end
end
