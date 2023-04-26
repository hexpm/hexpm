defmodule HexpmWeb.API.DocsController do
  use HexpmWeb, :controller

  @tarball_max_size 16 * 1024 * 1024

  plug :fetch_release

  plug :authorize,
       [
         domains: [{"api", "read"}],
         fun: [{AuthHelpers, :organization_access}, {AuthHelpers, :organization_billing_active}]
       ]
       when action in [:show]

  plug :authorize,
       [
         domains: [{"api", "write"}, "package"],
         fun: [{AuthHelpers, :package_owner}, {AuthHelpers, :organization_billing_active}]
       ]
       when action in [:create, :delete]

  def show(conn, _params) do
    repository = conn.assigns.repository
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: Hexpm.Utils.docs_tarball_url(repository, package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) when byte_size(body) > @tarball_max_size do
    validation_failed(conn, %{tar: "too big"})
  end

  def create(conn, %{"body" => body}) do
    repository = conn.assigns.repository
    package = conn.assigns.package
    release = conn.assigns.release
    request_id = List.first(get_resp_header(conn, "x-request-id"))

    log_tarball(repository.name, package.name, release.version, request_id, body)
    Hexpm.Repository.Releases.publish_docs(package, release, body, audit: audit_data(conn))

    location = Hexpm.Utils.docs_tarball_url(repository, package, release)

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

  defp log_tarball(repository, package, version, request_id, body) do
    Task.Supervisor.start_child(Hexpm.Tasks, fn ->
      filename = "#{repository}-#{package}-#{version}-#{request_id}.tar.gz"
      key = Path.join(["debug", "docs", filename])
      Hexpm.Store.put(:repo_bucket, key, body, [])
    end)
  end
end
