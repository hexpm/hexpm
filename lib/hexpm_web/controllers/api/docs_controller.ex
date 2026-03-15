defmodule HexpmWeb.API.DocsController do
  use HexpmWeb, :controller

  @tarball_max_size 16 * 1024 * 1024
  @tarball_max_uncompressed_size 128 * 1024 * 1024

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

  plug :handle_100_continue, [max_size: @tarball_max_size] when action in [:create]

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

  def create(conn, %{"body" => body_path}) do
    %{size: size} = File.stat!(body_path)

    cond do
      size > @tarball_max_size ->
        validation_failed(conn, %{tar: "too big"})

      gzip_too_large?(body_path) ->
        validation_failed(conn, %{tar: "too big (uncompressed)"})

      true ->
        repository = conn.assigns.repository
        package = conn.assigns.package
        release = conn.assigns.release
        request_id = List.first(get_resp_header(conn, "x-request-id"))

        log_tarball(repository.name, package.name, release.version, request_id, body_path)

        Hexpm.Repository.Releases.publish_docs(package, release, body_path,
          audit: audit_data(conn)
        )

        location = Hexpm.Utils.docs_tarball_url(repository, package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> send_resp(201, "")
    end
  end

  def delete(conn, _params) do
    Hexpm.Repository.Releases.revert_docs(conn.assigns.release, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp gzip_too_large?(path) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, 16 + 15)
      data = File.read!(path)
      gzip_too_large_loop?(z, data, 0)
    after
      :zlib.close(z)
    end
  end

  defp gzip_too_large_loop?(z, data, size) do
    case :zlib.safeInflate(z, data) do
      {:continue, output} ->
        new_size = size + IO.iodata_length(output)

        if new_size > @tarball_max_uncompressed_size do
          true
        else
          gzip_too_large_loop?(z, [], new_size)
        end

      {:finished, output} ->
        size + IO.iodata_length(output) > @tarball_max_uncompressed_size
    end
  end

  defp log_tarball(repository, package, version, request_id, body_path) do
    # Use random ID instead of user-controlled request_id in key to prevent overwrites
    random_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    filename = "#{repository}-#{package}-#{version}-#{random_id}.tar.gz"
    key = Path.join(["debug", "docs", filename])
    # Store request_id in metadata for debugging (ignored by Store.Local)
    opts = [cache_control: "private", meta: %{"request-id" => request_id || "unknown"}]
    Hexpm.Store.put_file(:repo_bucket, key, body_path, opts)
  end
end
