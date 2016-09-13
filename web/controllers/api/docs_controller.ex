defmodule HexWeb.API.DocsController do
  use HexWeb.Web, :controller

  plug :fetch_release
  plug :authorize, [fun: &package_owner?/2] when action != :show

  def show(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: HexWeb.Utils.docs_tarball_url(package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) do
    package = conn.assigns.package
    release = conn.assigns.release

    case HexWeb.DocsTar.parse(body) do
      {:ok, {files, body}} ->
        HexWeb.Releases.publish_docs(package, release, files, body, audit: audit_data(conn))
        location = HexWeb.Utils.docs_tarball_url(package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> send_resp(201, "")
      {:error, errors} ->
        validation_failed(conn, [tar: errors])
    end
  end

  def delete(conn, _params) do
    HexWeb.Releases.revert_docs(conn.assigns.release, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end
end
