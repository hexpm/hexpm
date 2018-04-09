defmodule Hexpm.Web.API.DocsController do
  use Hexpm.Web, :controller

  plug :fetch_release

  plug :maybe_authorize,
       [
         domain: "api",
         resource: "read",
         fun: [&repository_access/2, &repository_billing_active/2]
       ]
       when action in [:show]

  plug :authorize,
       [domain: "api", resource: "write", fun: [&package_owner/2, &repository_billing_active/2]]
       when action in [:create, :delete]

  def show(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: Hexpm.Utils.docs_tarball_url(package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) do
    package = conn.assigns.package
    release = conn.assigns.release

    case Hexpm.Web.DocsTar.parse(body) do
      {:ok, {files, body}} ->
        Hexpm.Repository.Releases.publish_docs(
          package,
          release,
          files,
          body,
          audit: audit_data(conn)
        )

        location = Hexpm.Utils.docs_tarball_url(package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> send_resp(201, "")

      {:error, errors} ->
        validation_failed(conn, %{tar: errors})
    end
  end

  def delete(conn, _params) do
    Hexpm.Repository.Releases.revert_docs(conn.assigns.release, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end
end
