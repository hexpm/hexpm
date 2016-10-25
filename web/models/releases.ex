defmodule HexWeb.Releases do
  use HexWeb.Web, :crud

  @publish_timeout 60_000

  def all(package) do
    Release.all(package)
    |> Repo.all
    |> Release.sort
  end

  def recent(count) do
    Repo.all(Release.recent(count))
  end

  def count do
    Repo.one!(Release.count)
  end

  def get(package, version) do
    release = Repo.get_by(assoc(package, :releases), version: version)
    release && %{release | package: package}
  end

  def package_versions(packages) do
    Release.package_versions(packages)
    |> Repo.all
    |> Enum.into(%{})
  end

  def preload(release) do
    Repo.preload(release,
      requirements: Release.requirements(release),
      downloads: ReleaseDownload.release(release))
  end

  def publish(package, user, body, meta, checksum, [audit: audit_data]) do
    Multi.new
    |> create_package(package, user, meta)
    |> create_release(package, checksum, meta)
    |> audit_publish(audit_data)
    |> publish_release(body)
    |> Repo.transaction(timeout: @publish_timeout)
    |> publish_result
  end

  def publish_docs(package, release, files, body, [audit: audit_data]) do
    version        = to_string(release.version)
    latest_version = from(r in Release.all(package), select: r.version, where: r.has_docs == true or r.version == ^version)
                     |> Repo.all
                     |> Enum.reject(fn(version) -> version.pre != [] end)
                     |> Enum.sort(&Version.compare(&1, &2) == :gt)
                     |> List.first

    docs_for_latest_release = (latest_version != nil) && (release.version == latest_version)

    Assets.push_docs(release, files, body, docs_for_latest_release)

    multi =
      Multi.new
      |> Multi.update(:release, Ecto.Changeset.change(release, has_docs: true))
      |> Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: HexWeb.Utils.utc_now))
      |> audit(audit_data, "docs.publish", {package, release})

    {:ok, _} = Repo.transaction(multi)

    Sitemaps.publish_docs_sitemap()
  end

  def revert(package, release, [audit: audit_data]) do
    delete_query =
      from(p in Package,
        where: p.id == ^package.id,
        where: fragment("NOT EXISTS (SELECT id FROM releases WHERE package_id = ?)", ^package.id)
      )

    Multi.new
    |> Multi.delete(:release, Release.delete(release))
    |> audit_revert(audit_data, package, release)
    |> Multi.delete_all(:package, delete_query)
    |> Repo.transaction_with_isolation(level: :serializable, timeout: @publish_timeout)
    |> revert_result(package)
  end

  def revert_docs(release, [audit: audit_data]) do
    multi =
      Multi.new
      |> Multi.update(:release, Ecto.Changeset.change(release, has_docs: false))
      |> Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: HexWeb.Utils.utc_now))
      |> audit(audit_data, "docs.revert", {release.package, release})

    {:ok, _} = Repo.transaction(multi)

    Assets.revert_docs(release)
  end

  defp publish_result({:ok, %{package: package}} = result) do
    RegistryBuilder.partial_build({:publish, package.name})
    result
  end
  defp publish_result(result), do: result

  defp revert_result({:ok, %{release: release}}, package) do
    Assets.revert_release(release)
    RegistryBuilder.partial_build({:revert, package.name})
    :ok
  end
  defp revert_result(result, _package), do: result

  defp create_package(multi, package, user, meta) do
    params = %{"name" => meta["name"], "meta" => meta}
    if package do
      Multi.update(multi, :package, Package.update(package, params))
    else
      Multi.insert(multi, :package, Package.build(user, params))
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
      |> Multi.update(:release, Release.update(release, params, checksum))
      |> Multi.run(:action, fn _ -> {:ok, :update} end)
    else
      multi
      |> build_release(params, checksum)
      |> Multi.run(:action, fn _ -> {:ok, :insert} end)
    end
  end

  defp build_release(multi, params, checksum) do
    Multi.merge(multi, fn %{package: package} ->
      Multi.insert(Multi.new, :release, Release.build(package, params, checksum))
    end)
  end

  defp audit_publish(multi, audit_data) do
    audit(multi, audit_data, "release.publish", fn %{package: pkg, release: rel} -> {pkg, rel} end)
  end

  defp audit_revert(multi, audit_data, package, release) do
    audit(multi, audit_data, "release.revert", {package, release})
  end

  defp publish_release(multi, body) do
    Multi.run(multi, :assets, fn %{package: package, release: release} ->
      release = %{release | package: package}
      Assets.push_release(release, body)
      {:ok, :ok}
    end)
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
