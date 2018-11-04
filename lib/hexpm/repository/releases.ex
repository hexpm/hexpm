defmodule Hexpm.Repository.Releases do
  use HexpmWeb, :context

  @publish_timeout 60_000

  def all(package) do
    Release.all(package)
    |> Repo.all()
    |> Release.sort()
  end

  def recent(organization, count) do
    Repo.all(Release.recent(organization, count))
  end

  def count() do
    Repo.one!(Release.count())
  end

  def get(package, version) do
    release = Repo.get_by(assoc(package, :releases), version: version)
    release && %{release | package: package}
  end

  def get(organization, package, version) when is_binary(package) do
    package = Packages.get(organization, package)
    package && get(package, version)
  end

  def package_versions(packages) do
    Release.package_versions(packages)
    |> Repo.all()
    |> Enum.into(%{})
  end

  def preload(release, keys) do
    preload = Enum.map(keys, &preload_field(release, &1))
    Repo.preload(release, preload)
  end

  def publish(organization, package, user, body, meta, checksum, audit: audit_data) do
    Multi.new()
    |> Multi.run(:organization, fn _, _ -> {:ok, organization} end)
    |> Multi.run(:reserved_packages, fn _, _ -> {:ok, reserved_packages(organization, meta)} end)
    |> create_package(organization, package, user, meta)
    |> create_release(package, checksum, meta)
    |> audit_publish(audit_data)
    |> refresh_package_dependants()
    |> Repo.transaction(timeout: @publish_timeout)
    |> publish_result(body)
  end

  def publish_docs(package, release, body, audit: audit_data) do
    Assets.push_docs(release, body)

    now = DateTime.utc_now()
    release_changeset = Ecto.Changeset.change(release, has_docs: true)
    package_changeset = Ecto.Changeset.change(release.package, docs_updated_at: now)

    {:ok, _} =
      Multi.new()
      |> Multi.update(:release, release_changeset)
      |> Multi.update(:package, package_changeset)
      |> audit(audit_data, "docs.publish", {package, release})
      |> Repo.transaction()
  end

  def revert(package, release, audit: audit_data) do
    Multi.new()
    |> Multi.delete(:release, Release.delete(release))
    |> audit_revert(audit_data, package, release)
    |> Multi.run(:package, &maybe_delete_package/2)
    |> refresh_package_dependants()
    |> Repo.transaction(timeout: @publish_timeout)
    |> revert_result(package)
  end

  def revert_docs(release, audit: audit_data) do
    now = DateTime.utc_now()
    release_changeset = Ecto.Changeset.change(release, has_docs: false)
    package_changeset = Ecto.Changeset.change(release.package, docs_updated_at: now)

    {:ok, _} =
      Multi.new()
      |> Multi.update(:release, release_changeset)
      |> Multi.update(:package, package_changeset)
      |> audit(audit_data, "docs.revert", {release.package, release})
      |> Repo.transaction()

    Assets.revert_docs(release)
  end

  def retire(package, release, params, audit: audit_data) do
    params = %{"retirement" => params}

    Multi.new()
    |> Multi.run(:organization, fn _, _ -> {:ok, package.organization} end)
    |> Multi.run(:package, fn _, _ -> {:ok, package} end)
    |> Multi.update(:release, Release.retire(release, params))
    |> audit_retire(audit_data, package)
    |> Repo.transaction()
    |> publish_result(nil)
  end

  def unretire(package, release, audit: audit_data) do
    Multi.new()
    |> Multi.run(:organization, fn _, _ -> {:ok, package.organization} end)
    |> Multi.run(:package, fn _, _ -> {:ok, package} end)
    |> Multi.update(:release, Release.unretire(release))
    |> audit_unretire(audit_data, package)
    |> Repo.transaction()
    |> publish_result(nil)
  end

  def downloads_by_period(package, filter) do
    if filter in ["day", "month"] do
      Release.downloads_by_period(package, filter)
      |> Repo.all()
    else
      Release.downloads_by_period(package, "all")
      |> Repo.one()
    end
  end

  defp publish_result({:ok, result}, body) do
    package = %{result.package | organization: result.organization}
    release = %{result.release | package: package}

    if body, do: Assets.push_release(release, body)
    RegistryBuilder.partial_build({:publish, package})
    {:ok, %{result | release: release, package: package}}
  end

  defp publish_result(result, _body), do: result

  defp revert_result({:ok, %{release: release}}, package) do
    Assets.revert_release(release)
    RegistryBuilder.partial_build({:publish, package})
    :ok
  end

  defp revert_result(result, _package), do: result

  defp create_package(multi, organization, package, user, meta) do
    changeset =
      if package do
        params = %{"meta" => meta}
        Package.update(package, params)
      else
        params = %{"name" => meta["name"], "meta" => meta}
        Package.build(organization, user, params)
      end

    Multi.insert_or_update(multi, :package, fn %{reserved_packages: reserved_packages} ->
      validate_reserved_package(changeset, reserved_packages)
    end)
  end

  defp create_release(multi, package, checksum, meta) do
    version = meta["version"]

    params = %{
      "app" => meta["app"],
      "version" => version,
      "requirements" => normalize_requirements(meta["requirements"]),
      "meta" => meta
    }

    release = package && Repo.get_by(assoc(package, :releases), version: version)

    multi
    |> Multi.insert_or_update(:release, fn %{
                                             package: package,
                                             reserved_packages: reserved_packages
                                           } ->
      changeset =
        if release do
          %{release | package: package}
          |> Repo.preload(requirements: Release.requirements(release))
          |> Release.update(params, checksum)
        else
          Release.build(package, params, checksum)
        end

      validate_reserved_version(changeset, reserved_packages)
    end)
    |> Multi.run(:action, fn _, _ -> {:ok, if(release, do: :update, else: :insert)} end)
  end

  defp refresh_package_dependants(multi) do
    Multi.run(multi, :refresh, fn repo, _ ->
      :ok = repo.refresh_view(Hexpm.Repository.PackageDependant)
      {:ok, :refresh}
    end)
  end

  defp maybe_delete_package(repo, %{release: release}) do
    count = repo.aggregate(assoc(release.package, :releases), :count, :id)

    if count == 0 do
      release.package
      |> Package.delete()
      |> repo.delete()
    else
      :ok
    end
  end

  defp reserved_packages(organization, %{"name" => name}) when is_binary(name) do
    from(
      r in "reserved_packages",
      where: r.organization_id == ^organization.id,
      where: r.name == ^name,
      select: r.version
    )
    |> Repo.all()
    |> Enum.map(fn version ->
      if version do
        {:ok, version} = Version.parse(version)
        version
      end
    end)
  end

  defp reserved_packages(_organization, _meta) do
    []
  end

  defp validate_reserved_package(changeset, reserved) do
    if nil in reserved do
      validate_exclusion(changeset, :name, [get_field(changeset, :name)])
    else
      changeset
    end
  end

  defp validate_reserved_version(changeset, reserved) do
    validate_exclusion(changeset, :version, reserved)
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

  defp normalize_requirements(requirements) when is_map(requirements) do
    Enum.map(requirements, fn
      {name, map} when is_map(map) ->
        Map.put(map, "name", name)

      other ->
        other
    end)
  end

  defp normalize_requirements(requirements), do: requirements

  defp preload_field(release, :requirements), do: {:requirements, Release.requirements(release)}
  defp preload_field(release, :downloads), do: {:downloads, ReleaseDownload.release(release)}
end
