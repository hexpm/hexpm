defmodule HexWeb.API.ReleaseController do
  use HexWeb.Web, :controller

  @publish_timeout 60_000

  plug :fetch_release when action in [:show, :delete]
  plug :maybe_fetch_package when action in [:create]
  plug :authorize, [fun: &package_owner?/2] when action in [:delete]
  plug :authorize, [fun: &maybe_package_owner?/2] when action in [:create]

  def create(conn, %{"body" => body}) do
    handle_tarball(conn, conn.assigns[:package], conn.assigns.user, body)
  end

  def show(conn, _params) do
    release = conn.assigns.release

    release =
      HexWeb.Repo.preload(release,
        requirements: Release.requirements(release),
        downloads: ReleaseDownload.release(release))

    when_stale(conn, release, fn conn ->
      conn
      |> api_cache(:public)
      |> render(:show, release: release)
    end)
  end

  def delete(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    delete_query =
      from(p in Package,
        where: p.id == ^package.id,
        where: fragment("NOT EXISTS (SELECT id FROM releases WHERE package_id = ?)", ^package.id)
      )

    Ecto.Multi.new
    |> Ecto.Multi.delete(:release, Release.delete(release))
    |> audit(conn, "release.revert", {package, release})
    |> Ecto.Multi.delete_all(:package, delete_query)
    |> HexWeb.Repo.transaction_with_isolation(level: :serializable, timeout: @publish_timeout)
    |> delete_result(conn, release)
  end

  def delete_result({:ok, _}, conn, release) do
    revert_assets(release)
    HexWeb.RegistryBuilder.rebuild

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end
  def delete_result({:error, _, changeset, _}, conn, _release) do
    validation_failed(conn, changeset)
  end

  defp handle_tarball(conn, package, user, body) do
    case HexWeb.Tar.metadata(body) do
      {:ok, meta, checksum} ->
        Ecto.Multi.new
        |> create_package(package, user, meta)
        |> create_release(package, checksum, meta)
        |> audit_publish(user)
        |> publish_release(body)
        |> HexWeb.Repo.transaction(timeout: @publish_timeout)

      {:error, errors} ->
        {:error, %{tar: errors}}
    end
    |> publish_result(conn)
  end

  defp publish_result({:ok, %{action: :insert, package: package, release: release}}, conn) do
    HexWeb.RegistryBuilder.rebuild
    location = release_url(conn, :show, package, release)

    conn
    |> put_resp_header("location", location)
    |> api_cache(:public)
    |> put_status(201)
    |> render(:show, release: %{release | package: package})
  end
  defp publish_result({:ok, %{action: :update, package: package, release: release}}, conn) do
    HexWeb.RegistryBuilder.rebuild
    conn
    |> api_cache(:public)
    |> render(:show, release: %{release | package: package})
  end
  defp publish_result({:error, errors}, conn) do
    validation_failed(conn, errors)
  end
  defp publish_result({:error, _, changeset, _}, conn) do
    validation_failed(conn, normalize_errors(changeset))
  end

  defp create_package(multi, package, user, meta) do
    params = %{"name" => meta["name"], "meta" => meta}
    if package do
      Ecto.Multi.update(multi, :package, Package.update(package, params))
    else
      Ecto.Multi.insert(multi, :package, Package.build(user, params))
    end
  end

  defp create_release(multi, package, checksum, meta) do
    version = meta["version"]
    params = %{
      "app" => meta["app"],
      "version" => version,
      "requirements" => normalize_requirements(meta["requirements"]),
      "meta" => meta}

    release = package && HexWeb.Repo.get_by(assoc(package, :releases), version: version)

    if release do
      release = HexWeb.Repo.preload(release, requirements: Release.requirements(release))
      multi
      |> Ecto.Multi.update(:release, Release.update(release, params, checksum))
      |> Ecto.Multi.run(:action, fn _ -> {:ok, :update} end)
    else
      multi
      |> build_release(params, checksum)
      |> Ecto.Multi.run(:action, fn _ -> {:ok, :insert} end)
    end
  end

  defp build_release(multi, params, checksum) do
    Ecto.Multi.merge(multi, fn %{package: package} ->
      Ecto.Multi.insert(Ecto.Multi.new, :release, Release.build(package, params, checksum))
    end)
  end

  defp publish_release(multi, body) do
    Ecto.Multi.run(multi, :assets, fn %{package: package, release: release} ->
      push_assets(package, release.version, body)
      {:ok, :ok}
    end)
  end

  defp audit_publish(multi, user) do
    audit(multi, user, "release.publish", fn %{package: pkg, release: rel} -> {pkg, rel} end)
  end

  # Turn `%{"ecto" => %{"app" => "...", ...}}` into:
  #      `[%{"name" => "ecto", "app" => "...", ...}]` for cast_assoc
  defp normalize_requirements(requirements) when is_map(requirements) do
    Enum.map(requirements, fn
      {name, map} when is_map(map) ->
        Map.put(map, "name", name)
      other ->
        other
    end)
  end
  defp normalize_requirements(requirements), do: requirements

  defp normalize_errors(%{changes: %{requirements: requirements}} = changeset) do
    requirements =
      Enum.map(requirements, fn
        %{errors: errors} = req ->
          name = Ecto.Changeset.get_change(req, :name)
          %{req | errors: for({_, v} <- errors, do: {name, v}, into: %{})}
      end)

    put_in(changeset.changes.requirements, requirements)
  end
  defp normalize_errors(changeset), do: changeset

  defp push_assets(package, version, body) do
    cdn_key = "tarballs/#{package.name}-#{version}"
    store_key = "tarballs/#{package.name}-#{version}.tar"
    opts = [acl: :public_read, cache_control: "public, max-age=604800", meta: [{"surrogate-key", cdn_key}]]
    HexWeb.Store.put(nil, :s3_bucket, store_key, body, opts)
    HexWeb.CDN.purge_key(:fastly_hexrepo, cdn_key)
  end

  defp revert_assets(release) do
    name    = release.package.name
    version = to_string(release.version)
    key     = "tarballs/#{name}-#{version}.tar"

    # Delete release tarball
    HexWeb.Store.delete(nil, :s3_bucket, key, [])

    # Delete relevant documentation (if it exists)
    if release.has_docs do
      HexWeb.Store.delete(nil, :s3_bucket, "docs/#{name}-#{version}.tar.gz", [])
      paths = HexWeb.Store.list(nil, :docs_bucket, Path.join(name, version))
      HexWeb.Store.delete_many(nil, :docs_bucket, Enum.to_list(paths), [])
      HexWeb.API.DocsController.publish_sitemap
    end
  end
end
