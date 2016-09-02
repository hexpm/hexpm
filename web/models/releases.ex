defmodule HexWeb.Releases do
  use HexWeb.Web, :crud

  @publish_timeout 60_000

  def preload(release) do
    Repo.preload(release,
      requirements: Release.requirements(release),
      downloads: ReleaseDownload.release(release))
  end

  def publish(package, user, body, meta, checksum, [audit: audit_data]) do
    Ecto.Multi.new
    |> create_package(package, user, meta)
    |> create_release(package, checksum, meta)
    |> audit_publish(audit_data)
    |> publish_release(body)
    |> Repo.transaction(timeout: @publish_timeout)
    |> publish_result
  end

  def revert(package, release, [audit: audit_data]) do
    delete_query =
      from(p in Package,
        where: p.id == ^package.id,
        where: fragment("NOT EXISTS (SELECT id FROM releases WHERE package_id = ?)", ^package.id)
      )

    Ecto.Multi.new
    |> Ecto.Multi.delete(:release, Release.delete(release))
    |> audit_revert(audit_data, package, release)
    |> Ecto.Multi.delete_all(:package, delete_query)
    |> Repo.transaction_with_isolation(level: :serializable, timeout: @publish_timeout)
    |> revert_result(package)
  end

  defp publish_result({:ok, %{package: package}} = result) do
    HexWeb.RegistryBuilder.partial_build({:publish, package.name})
    result
  end
  defp publish_result(result), do: result

  defp revert_result({:ok, %{release: release}}, package) do
    revert_assets(release)
    HexWeb.RegistryBuilder.partial_build({:revert, package.name})
    :ok
  end
  defp revert_result(result, _package), do: result

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

    release = package && Repo.get_by(assoc(package, :releases), version: version)

    if release do
      release = Repo.preload(release, requirements: Release.requirements(release))
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

  defp audit_publish(multi, audit_data) do
    audit(multi, audit_data, "release.publish", fn %{package: pkg, release: rel} -> {pkg, rel} end)
  end

  defp audit_revert(multi, audit_data, package, release) do
    audit(multi, audit_data, "release.revert", {package, release})
  end

  defp publish_release(multi, body) do
    Ecto.Multi.run(multi, :assets, fn %{package: package, release: release} ->
      push_assets(package, release.version, body)
      {:ok, :ok}
    end)
  end

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

  defp normalize_requirements(requirements) when is_map(requirements) do
    Enum.map(requirements, fn
      {name, map} when is_map(map) ->
        Map.put(map, "name", name)
      other ->
        other
    end)
  end
  defp normalize_requirements(requirements), do: requirements
end
