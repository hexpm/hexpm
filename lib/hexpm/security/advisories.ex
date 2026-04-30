defmodule Hexpm.Security.Advisories do
  use Hexpm.Context

  import Ecto.Query

  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion

  def all(subject) do
    subject
    |> Advisory.all()
    |> where([a], is_nil(a.withdrawn_at))
    |> Repo.all()
    |> Repo.preload([:references, :affected_versions])
  end

  def upsert(records, package_ids) do
    Multi.new()
    |> Multi.run(:lock, fn repo, _ ->
      if repo.try_advisory_xact_lock?(:vulnerability_updater) do
        {:ok, :leader}
      else
        {:error, :not_leader}
      end
    end)
    |> upsert_advisories(records, package_ids)
    |> reconcile_advisories(records)
    |> Repo.transaction(timeout: 60_000)
  end

  def affected_versions_for_package(package_id) do
    Repo.all(
      from av in AdvisoryAffectedVersion,
        where: av.package_id == ^package_id
    )
  end

  defp upsert_advisories(multi, records, package_ids) do
    Enum.reduce(records, multi, fn record, multi ->
      Multi.run(multi, {:advisory, record.id}, fn repo, _ ->
        upsert_advisory(repo, record, package_ids)
      end)
    end)
  end

  defp upsert_advisory(repo, record, package_ids) do
    affected = filter_known_packages(record.affected, package_ids)

    advisory =
      case repo.get(Advisory, record.id) do
        nil -> %Advisory{id: record.id}
        existing -> repo.preload(existing, [:references, :affected_versions])
      end

    params = build_params(record, affected, package_ids)

    with {:ok, advisory} <- advisory |> Advisory.changeset(params) |> repo.insert_or_update() do
      {:ok, advisory} = sync_affected_packages(repo, advisory, affected, package_ids)
      sync_affected_releases(repo, advisory, affected, package_ids)
      {:ok, advisory}
    end
  end

  defp filter_known_packages(affected, package_ids) do
    Enum.filter(affected, fn %{package: name} -> Map.has_key?(package_ids, name) end)
  end

  defp build_params(record, affected, package_ids) do
    affected_version_params =
      Enum.flat_map(affected, fn %{package: name, requirements: requirements} ->
        package_id = Map.fetch!(package_ids, name)
        Enum.map(requirements, &%{package_id: package_id, requirement: &1})
      end)

    reference_params = Enum.map(record.references, &%{type: &1.type, url: &1.url})

    %{
      id: record.id,
      summary: record.summary,
      aliases: record.aliases,
      published_at: record.published_at,
      modified_at: record.modified_at,
      withdrawn_at: record.withdrawn_at,
      cvss_vector: record.cvss_vector,
      cvss_score: record.cvss_score,
      cvss_rating: record.cvss_rating,
      references: reference_params,
      affected_versions: affected_version_params
    }
  end

  defp sync_affected_packages(repo, advisory, affected, package_ids) do
    advisory_id = advisory.id

    repo.delete_all(
      from p in "security_advisory_affected_packages", where: p.advisory_id == ^advisory_id
    )

    rows =
      affected
      |> Enum.map(fn %{package: name} ->
        %{advisory_id: advisory_id, package_id: package_ids[name]}
      end)
      |> Enum.uniq()

    if rows != [] do
      repo.insert_all("security_advisory_affected_packages", rows)
    end

    {:ok, advisory}
  end

  defp sync_affected_releases(repo, advisory, affected, package_ids) do
    advisory_id = advisory.id

    repo.delete_all(
      from r in "security_advisory_affected_releases", where: r.advisory_id == ^advisory_id
    )

    release_ids =
      affected
      |> Enum.flat_map(fn %{package: name, requirements: requirements, versions: versions} ->
        package_id = Map.fetch!(package_ids, name)
        matching_release_ids(repo, package_id, requirements, versions)
      end)
      |> Enum.uniq()

    rows = Enum.map(release_ids, &%{advisory_id: advisory_id, release_id: &1})

    if rows != [] do
      repo.insert_all("security_advisory_affected_releases", rows)
    end

    :ok
  end

  defp matching_release_ids(repo, package_id, requirements, versions) do
    releases =
      repo.all(
        from r in Hexpm.Repository.Release,
          where: r.package_id == ^package_id,
          select: {r.id, r.version}
      )

    matching_by_requirement =
      for {id, version} <- releases,
          requirement <- requirements,
          Version.match?(version, requirement),
          do: id

    matching_by_version =
      for {id, version} <- releases,
          to_string(version) in versions,
          do: id

    Enum.uniq(matching_by_requirement ++ matching_by_version)
  end

  defp reconcile_advisories(multi, records) do
    seen_ids = Enum.map(records, & &1.id)

    Multi.delete_all(
      multi,
      :reconcile,
      from(a in Advisory, where: a.id not in ^seen_ids)
    )
  end

  def affect_release_with_existing_advisories(repo, release) do
    affected_versions = affected_versions_for_package_in_repo(repo, release.package_id)

    matching_advisory_ids =
      for av <- affected_versions,
          Version.match?(release.version, av.requirement),
          uniq: true,
          do: av.advisory_id

    rows = Enum.map(matching_advisory_ids, &%{advisory_id: &1, release_id: release.id})

    if rows != [] do
      repo.insert_all("security_advisory_affected_releases", rows, on_conflict: :nothing)
    end

    {:ok, matching_advisory_ids}
  end

  defp affected_versions_for_package_in_repo(repo, package_id) do
    repo.all(
      from av in AdvisoryAffectedVersion,
        where: av.package_id == ^package_id
    )
  end
end
