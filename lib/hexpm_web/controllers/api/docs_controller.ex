defmodule HexpmWeb.API.DocsController do
  use HexpmWeb, :controller

  plug :fetch_release

  plug :maybe_authorize,
       [
         domain: "api",
         resource: "read",
         fun: [&organization_access/2, &organization_billing_active/2]
       ]
       when action in [:show]

  plug :authorize,
       [domain: "api", resource: "write", fun: [&package_owner/2, &organization_billing_active/2]]
       when action in [:create, :delete]

  def show(conn, _params) do
    organization = conn.assigns.organization
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: Hexpm.Utils.docs_tarball_url(organization, package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) do
    organization = conn.assigns.organization
    package = conn.assigns.package
    release = conn.assigns.release
    request_id = List.first(get_req_header(conn, "x-request-id"))

    log_tarball(organization.name, package.name, release.version, request_id, body)
    Hexpm.Repository.Releases.publish_docs(package, release, body, audit: audit_data(conn))

    location = Hexpm.Utils.docs_tarball_url(organization, package, release)

    conn
    |> put_resp_header("location", location)
    |> api_cache(:public)
    |> send_resp(201, "")
  end

  def delete(conn, _params) do
    Hexpm.Repository.Releases.revert_docs(conn.assigns.release, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp log_tarball(organization, package, version, request_id, body) do
    filename = "#{organization}-#{package}-#{version}-#{request_id}.tar.gz"
    key = Path.join(["debug", "docs", filename])
    Hexpm.Store.put(nil, :s3_bucket, key, body, [])
  end
end
