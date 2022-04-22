defmodule Hexpm.Repository.Releases do
  use Hexpm.Context

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

  def preload(release, keys) do
    preload = Enum.map(keys, &preload_field(release, &1))
    Repo.preload(release, preload)
  end

  def publish(repository, package, user, body, meta, inner_checksum, outer_checksum,
        audit: audit_data,
        replace: replace?
      ) do
    Multi.new()
    |> Multi.run(:repository, fn _, _ -> {:ok, repository} end)
    |> Multi.run(:reserved_packages, fn _, _ -> {:ok, reserved_packages(repository, meta)} end)
    |> create_package(repository, package, user, meta)
    |> create_release(package, user, inner_checksum, outer_checksum, meta, replace?)
    |> audit_publish(audit_data)
    |> refresh_package_dependants()
    |> Repo.transaction(timeout: @publish_timeout)
    |> publish_result(user, body)
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
    |> Multi.run(:release_count, &release_count/2)
    |> Multi.run(:package, &maybe_delete_package/2)
    |> refresh_package_dependants()
    |> Repo.transaction(timeout: @publish_timeout)
    |> revert_result()
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
    |> Multi.run(:repository, fn _, _ -> {:ok, package.repository} end)
    |> Multi.run(:package, fn _, _ -> {:ok, package} end)
    |> Multi.update(:release, Release.retire(release, params))
    |> audit_retire(audit_data, package)
    |> Repo.transaction()
    |> retire_result()
  end

  def unretire(package, release, audit: audit_data) do
    Multi.new()
    |> Multi.run(:repository, fn _, _ -> {:ok, package.repository} end)
    |> Multi.run(:package, fn _, _ -> {:ok, package} end)
    |> Multi.update(:release, Release.unretire(release))
    |> audit_unretire(audit_data, package)
    |> Repo.transaction()
    |> retire_result()
  end

  def downloads_by_period(package, filter) do
    Release.downloads_by_period(package, filter || :all)
    |> Repo.all()
  end

  def downloads_for_last_n_days(release_id, num_of_days) do
    Release.downloads_for_last_n_days(release_id, num_of_days)
    |> Repo.all()
  end

  defp publish_result({:ok, %{package: package, release: release} = result}, user, body) do
    release = %{release | package: package}

    Assets.push_release(release, body)
    update_package_in_registry(package)
    email_package_owners(package, release, user)

    {:ok, %{result | release: release, package: package}}
  end

  defp publish_result(result, _user, _body), do: result

  defp retire_result({:ok, %{package: package}}) do
    RegistryBuilder.package(package)
    :ok
  end

  defp retire_result(result), do: result

  defp revert_result({:ok, %{package: package, release: release, release_count: 0}}) do
    remove_package_from_registry(package)
    Assets.revert_release(release)
    :ok
  end

  defp revert_result({:ok, %{package: package, release: release, release_count: _}}) do
    update_package_in_registry(package)
    Assets.revert_release(release)
    :ok
  end

  defp revert_result(result), do: result

  defp create_package(multi, repository, package, user, meta) do
    changeset =
      if package do
        params = %{"meta" => meta}
        Package.update(package, params)
      else
        params = %{"name" => meta["name"], "meta" => meta}
        Package.build(repository, user, params)
      end

    Multi.insert_or_update(multi, :package, fn %{reserved_packages: reserved_packages} ->
      validate_reserved_package(changeset, reserved_packages)
    end)
  end

  defp create_release(multi, package, user, inner_checksum, outer_checksum, meta, replace?) do
    version = meta["version"]

    # Validate version manually to avoid an Ecto.Query.CastError exception
    # which would return an opaque 400 HTTP status
    case Version.parse(version) do
      {:ok, version} ->
        params = %{
          "app" => meta["app"],
          "version" => version,
          "requirements" => normalize_requirements(meta["requirements"]),
          "meta" => meta
        }

        release = package && Repo.get_by(assoc(package, :releases), version: version)

        multi
        |> Multi.insert_or_update(:release, fn changes ->
          %{package: package, reserved_packages: reserved_packages} = changes

          changeset =
            if release do
              %{release | package: package}
              |> preload([:requirements, :publisher])
              |> Release.update(user, params, inner_checksum, outer_checksum, replace?)
            else
              Release.build(package, user, params, inner_checksum, outer_checksum, replace?)
            end

          validate_reserved_version(changeset, reserved_packages)
        end)
        |> Multi.run(:action, fn _, _ -> {:ok, if(release, do: :update, else: :insert)} end)

      :error ->
        params = %{version: Hexpm.Version}
        change = Ecto.Changeset.cast({%{}, params}, %{version: version}, ~w(version)a)
        Ecto.Multi.error(multi, :version, change)
    end
  end

  defp refresh_package_dependants(multi) do
    Multi.run(multi, :refresh, fn repo, _ ->
      :ok = repo.refresh_view(Hexpm.Repository.PackageDependant)
      {:ok, :refresh}
    end)
  end

  defp release_count(repo, %{release: release}) do
    {:ok, repo.aggregate(assoc(release.package, :releases), :count, :id)}
  end

  defp maybe_delete_package(repo, %{release_count: release_count, release: release}) do
    if release_count == 0 do
      release.package
      |> Package.delete()
      |> repo.delete()
    else
      {:ok, release.package}
    end
  end

  defp email_package_owners(package, release, publisher) do
    Hexpm.Repo.all(assoc(package, :owners))
    |> Hexpm.Repo.preload([:emails, organization: [users: :emails]])
    |> Emails.package_published(publisher, package.name, release.version)
    |> Mailer.deliver_later!()
  end

  if Mix.env() == :test do
    defp update_package_in_registry(package) do
      RegistryBuilder.package(package)
      RegistryBuilder.repository(package.repository)
    end

    defp remove_package_from_registry(package) do
      RegistryBuilder.package_delete(package)
      RegistryBuilder.repository(package.repository)
    end
  else
    defp update_package_in_registry(package) do
      RegistryBuilder.package(package)
      metadata = Logger.metadata()

      Task.Supervisor.start_child(Hexpm.Tasks, fn ->
        Logger.metadata(metadata)
        RegistryBuilder.repository(package.repository)
      end)
    end

    defp remove_package_from_registry(package) do
      RegistryBuilder.package_delete(package)
      metadata = Logger.metadata()

      Task.Supervisor.start_child(Hexpm.Tasks, fn ->
        Logger.metadata(metadata)
        RegistryBuilder.repository(package.repository)
      end)
    end
  end

  defp reserved_packages(repository, %{"name" => name}) when is_binary(name) do
    from(
      r in "reserved_packages",
      where: r.repository_id == ^repository.id,
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

  defp reserved_packages(_repository, _meta) do
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
  defp preload_field(_release, :publisher), do: {:publisher, [:emails, :organization]}
end
