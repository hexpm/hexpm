defmodule Hexpm.Repository.Releases do
  use Hexpm.Web, :context

  @publish_timeout 60_000

  def all(package) do
    Release.all(package)
    |> Repo.all()
    |> Release.sort()
  end

  def recent(repository, count) do
    Repo.all(Release.recent(repository, count))
  end

  def count() do
    Repo.one!(Release.count())
  end

  def get(package, version) do
    release = Repo.get_by(assoc(package, :releases), version: version)
    release && %{release | package: package}
  end

  def get(repository, package, version) when is_binary(package) do
    package = Packages.get(repository, package)
    package && get(package, version)
  end

  def package_versions(packages) do
    Release.package_versions(packages)
    |> Repo.all()
    |> Enum.into(%{})
  end

  def preload(release) do
    Repo.preload(release,
      requirements: Release.requirements(release),
      downloads: ReleaseDownload.release(release))
  end

  def publish(repository, package, user, body, meta, checksum, [audit: audit_data]) do
    Multi.new()
    |> create_package(repository, package, user, meta)
    |> create_release(package, checksum, meta)
    |> audit_publish(audit_data)
    |> publish_release(body)
    |> refresh_package_dependants()
    |> Repo.transaction(timeout: @publish_timeout)
    |> publish_result()
  end

  def publish_docs(package, release, files, body, [audit: audit_data]) do
    version        = to_string(release.version)
    latest_version =
      from(r in Release.all(package),
        where: r.has_docs == true or r.version == ^version,
        select: r.version)
      |> Repo.all()
      |> Enum.reject(&(&1.pre != []))
      |> Enum.sort(&Version.compare(&1, &2) == :gt)
      |> List.first()

    docs_for_latest_release = (latest_version != nil) && (release.version == latest_version)

    Assets.push_docs(release, files, body, docs_for_latest_release)

    multi =
      Multi.new()
      |> Multi.update(:release, Ecto.Changeset.change(release, has_docs: true))
      |> Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: NaiveDateTime.utc_now))
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

    Multi.new()
    |> Multi.delete(:release, Release.delete(release))
    |> audit_revert(audit_data, package, release)
    |> Multi.delete_all(:package, delete_query)
    |> refresh_package_dependants()
    |> Repo.transaction_with_isolation(level: :serializable, timeout: @publish_timeout)
    |> revert_result(package)
  end

  def revert_docs(release, [audit: audit_data]) do
    multi =
      Multi.new()
      |> Multi.update(:release, Ecto.Changeset.change(release, has_docs: false))
      |> Multi.update(:package, Ecto.Changeset.change(release.package, docs_updated_at: NaiveDateTime.utc_now))
      |> audit(audit_data, "docs.revert", {release.package, release})

    {:ok, _} = Repo.transaction(multi)

    Assets.revert_docs(release)
  end

  def retire(package, release, params, [audit: audit_data]) do
    params = %{"retirement" => params}

    Multi.new()
    |> Multi.run(:package, fn _ -> {:ok, package} end)
    |> Multi.update(:release, Release.retire(release, params))
    |> audit_retire(audit_data, package)
    |> Repo.transaction()
    |> publish_result()
  end

  def unretire(package, release, [audit: audit_data]) do
    Multi.new()
    |> Multi.run(:package, fn _ -> {:ok, package} end)
    |> Multi.update(:release, Release.unretire(release))
    |> audit_unretire(audit_data, package)
    |> Repo.transaction()
    |> publish_result()
  end

  defp publish_result({:ok, %{package: package}} = result) do
    RegistryBuilder.partial_build({:publish, package.name})
    result
  end
  defp publish_result(result), do: result

  defp revert_result({:ok, %{release: release}}, package) do
    Assets.revert_release(release)
    RegistryBuilder.partial_build({:publish, package.name})
    :ok
  end
  defp revert_result(result, _package), do: result

  defp create_package(multi, repository, package, user, meta) do
    params = %{"name" => meta["name"], "meta" => meta}
    cond do
      !package ->
        Multi.insert(multi, :package, Package.build(repository, user, params))
      package.name != meta["name"] ->
        changeset =
          Package.build(repository, user, params)
          |> add_error(:name, "mismatch between metadata and endpoint")
        Multi.update(multi, :package, changeset)
      true ->
        Multi.update(multi, :package, Package.update(package, params))
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

  defp refresh_package_dependants(multi) do
    Multi.run(multi, :refresh, fn _ ->
      :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)
      {:ok, :refresh}
    end)
  end

  defp audit_publish(multi, audit_data) do
    audit(multi, audit_data, "release.publish", fn %{package: pkg, release: rel} -> {pkg, rel} end)
  end

  defp audit_revert(multi, audit_data, package, release) do
    audit(multi, audit_data, "release.revert", {package, release})
  end

  defp audit_retire(multi, audit_data, package) do
    audit(multi, audit_data, "release.retire", fn %{release: rel} -> {package, rel} end)
  end

  defp audit_unretire(multi, audit_data, package) do
    audit(multi, audit_data, "release.unretire", fn %{release: rel} -> {package, rel} end)
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
