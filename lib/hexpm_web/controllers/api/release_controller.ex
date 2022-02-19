defmodule HexpmWeb.API.ReleaseController do
  use HexpmWeb, :controller

  plug :parse_tarball when action in [:publish]
  plug :maybe_fetch_release when action in [:show]
  plug :fetch_release when action in [:delete]
  plug :maybe_fetch_package when action in [:create, :publish]

  plug :authorize,
       [domain: "api", resource: "read", fun: &organization_access/2]
       when action in [:show]

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: [&package_owner/2, &organization_billing_active/2]
       ]
       when action in [:create, :publish]

  plug :authorize,
       [
         domain: "api",
         resource: "write",
         fun: [&package_owner/2, &organization_billing_active/2]
       ]
       when action in [:delete]

  @download_period_params ~w(day month all)

  def publish(conn, %{"body" => body} = params) do
    replace? = Map.get(params, "replace", true)
    request_id = List.first(get_resp_header(conn, "x-request-id"))

    log_tarball(
      conn.assigns.repository.name,
      conn.assigns.meta["name"],
      conn.assigns.meta["version"],
      request_id,
      body
    )

    Releases.publish(
      conn.assigns.repository,
      conn.assigns.package,
      conn.assigns.current_user,
      body,
      conn.assigns.meta,
      conn.assigns.inner_checksum,
      conn.assigns.outer_checksum,
      audit: audit_data(conn),
      replace: replace?
    )
    |> publish_result(conn)
  end

  def create(conn, %{"body" => body}) do
    handle_tarball(
      conn,
      conn.assigns.repository,
      conn.assigns.package,
      conn.assigns.current_user,
      body
    )
  end

  def show(conn, params) do
    if release = conn.assigns.release do
      downloads_period = Hexpm.Utils.safe_to_atom(params["downloads"], @download_period_params)
      downloads = Releases.downloads_by_period(release.id, downloads_period)

      release =
        release
        |> Releases.preload([:requirements, :publisher])
        |> Map.put(:downloads, downloads)

      when_stale(conn, release, fn conn ->
        conn
        |> api_cache(:public)
        |> render(:show, release: release)
      end)
    else
      not_found(conn)
    end
  end

  def delete(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    case Releases.revert(package, release, audit: audit_data(conn)) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")

      {:error, _, changeset, _} ->
        validation_failed(conn, changeset)
    end
  end

  defp parse_tarball(conn, _opts) do
    case release_metadata(conn.params["body"]) do
      {:ok, meta, inner_checksum, outer_checksum} ->
        params = Map.put(conn.params, "name", meta["name"])

        %{conn | params: params}
        |> assign(:meta, meta)
        |> assign(:inner_checksum, inner_checksum)
        |> assign(:outer_checksum, outer_checksum)

      {:error, errors} ->
        validation_failed(conn, %{tar: errors})
    end
  end

  defp handle_tarball(conn, repository, package, user, body) do
    case release_metadata(body) do
      {:ok, meta, inner_checksum, outer_checksum} ->
        replace? = Map.get(conn.params, "replace", true)
        request_id = List.first(get_resp_header(conn, "x-request-id"))
        log_tarball(repository.name, meta["name"], meta["version"], request_id, body)

        Releases.publish(
          repository,
          package,
          user,
          body,
          meta,
          inner_checksum,
          outer_checksum,
          audit: audit_data(conn),
          replace: replace?
        )

      {:error, errors} ->
        {:error, %{tar: errors}}
    end
    |> publish_result(conn)
  end

  defp publish_result({:ok, %{action: :insert, package: package, release: release}}, conn) do
    location = Routes.api_release_url(conn, :show, package, release)

    conn
    |> put_resp_header("location", location)
    |> api_cache(:public)
    |> put_status(201)
    |> render(:show, release: release)
  end

  defp publish_result({:ok, %{action: :update, release: release}}, conn) do
    conn
    |> api_cache(:public)
    |> render(:show, release: release)
  end

  defp publish_result({:error, errors}, conn) do
    validation_failed(conn, errors)
  end

  defp publish_result({:error, _, changeset, _}, conn) do
    validation_failed(conn, normalize_errors(changeset))
  end

  defp normalize_errors(%{changes: %{requirements: requirements}} = changeset) do
    requirements =
      Enum.map(requirements, fn %{errors: errors} = req ->
        name = Ecto.Changeset.get_field(req, :name)
        %{req | errors: for({_, v} <- errors, do: {name, v}, into: %{})}
      end)

    put_in(changeset.changes.requirements, requirements)
  end

  defp normalize_errors(changeset), do: changeset

  defp log_tarball(repository, package, version, request_id, body) do
    filename = "#{repository}-#{package}-#{version}-#{request_id}.tar.gz"
    key = Path.join(["debug", "tarballs", filename])
    Hexpm.Store.put(:repo_bucket, key, body, [])
  end

  defp release_metadata(tarball) do
    case :hex_tarball.unpack(tarball, :memory) do
      {:ok, %{inner_checksum: inner_checksum, outer_checksum: outer_checksum, metadata: metadata}} ->
        {:ok, metadata, inner_checksum, outer_checksum}

      {:error, reason} ->
        {:error, List.to_string(:hex_tarball.format_error(reason))}
    end
  end
end
