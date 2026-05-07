defmodule Hexpm.Security.Advisories do
  use Hexpm.Context

  import Ecto.Query

  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion

  @advisory_fields ~w(id summary aliases published_at modified_at withdrawn_at cvss_vector cvss_score cvss_rating)a

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
    |> upsert_advisories(records)
    |> prepare_changed(package_ids)
    |> sync_references()
    |> sync_affected_versions()
    |> sync_affected_packages()
    |> sync_affected_releases()
    |> reconcile_advisories(records)
    |> Repo.transaction(timeout: 60_000)
  end

  defp upsert_advisories(multi, records) do
    Multi.run(multi, :upsert_advisories, fn repo, _ ->
      with {:ok, rows} <- advisory_rows(records) do
        on_conflict_query =
          from(a in Advisory,
            update: [
              set: [
                summary: fragment("EXCLUDED.summary"),
                aliases: fragment("EXCLUDED.aliases"),
                modified_at: fragment("EXCLUDED.modified_at"),
                withdrawn_at: fragment("EXCLUDED.withdrawn_at"),
                cvss_vector: fragment("EXCLUDED.cvss_vector"),
                cvss_score: fragment("EXCLUDED.cvss_score"),
                cvss_rating: fragment("EXCLUDED.cvss_rating")
              ]
            ],
            where: fragment("? IS DISTINCT FROM EXCLUDED.modified_at", a.modified_at)
          )

        {_count, returned} =
          repo.insert_all(
            Advisory,
            rows,
            on_conflict: on_conflict_query,
            conflict_target: [:id],
            returning: [:id]
          )

        changed_ids = MapSet.new(returned, & &1.id)
        {:ok, Map.new(records, &{&1.id, &1}) |> Map.filter(fn {id, _} -> id in changed_ids end)}
      end
    end)
  end

  defp prepare_changed(multi, package_ids) do
    Multi.run(multi, :changed_advisories, fn _repo, %{upsert_advisories: changed_records} ->
      enriched =
        Map.new(changed_records, fn {id, record} ->
          affected =
            record.affected
            |> filter_known_packages(package_ids)
            |> Enum.map(fn entry -> Map.put(entry, :package_id, package_ids[entry.package]) end)

          {id, {record, affected}}
        end)

      {:ok, enriched}
    end)
  end

  defp advisory_rows(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      params = %{
        id: record.id,
        summary: record.summary,
        aliases: record.aliases,
        published_at: record.published_at,
        modified_at: record.modified_at,
        withdrawn_at: record.withdrawn_at,
        cvss_vector: record.cvss_vector,
        cvss_score: record.cvss_score,
        cvss_rating: record.cvss_rating
      }

      case %Advisory{} |> Advisory.changeset(params) |> Ecto.Changeset.apply_action(:insert) do
        {:ok, advisory} -> {:cont, {:ok, [Map.take(advisory, @advisory_fields) | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp filter_known_packages(affected, package_ids) do
    Enum.filter(affected, fn %{package: name} -> Map.has_key?(package_ids, name) end)
  end

  defp sync_references(multi) do
    multi
    |> Multi.delete_all(:delete_references, fn %{changed_advisories: changed} ->
      from(r in "security_advisory_references", where: r.advisory_id in ^Map.keys(changed))
    end)
    |> Multi.insert_all(:insert_references, "security_advisory_references", fn
      %{changed_advisories: changed} ->
        Enum.flat_map(changed, fn {id, {record, _affected}} ->
          Enum.map(record.references, &%{advisory_id: id, type: &1.type, url: &1.url})
        end)
    end)
  end

  defp sync_affected_versions(multi) do
    multi
    |> Multi.delete_all(:delete_affected_versions, fn %{changed_advisories: changed} ->
      from(v in "security_advisory_affected_versions",
        where: v.advisory_id in ^Map.keys(changed)
      )
    end)
    |> Multi.insert_all(:insert_affected_versions, "security_advisory_affected_versions", fn
      %{changed_advisories: changed} ->
        Enum.flat_map(changed, fn {id, {_record, affected}} ->
          Enum.flat_map(affected, fn %{package_id: package_id, requirements: requirements} ->
            Enum.map(
              requirements,
              &%{advisory_id: id, package_id: package_id, requirement: to_string(&1)}
            )
          end)
        end)
    end)
  end

  defp sync_affected_packages(multi) do
    multi
    |> Multi.delete_all(:delete_affected_packages, fn %{changed_advisories: changed} ->
      from(p in "security_advisory_affected_packages",
        where: p.advisory_id in ^Map.keys(changed)
      )
    end)
    |> Multi.insert_all(:insert_affected_packages, "security_advisory_affected_packages", fn
      %{changed_advisories: changed} ->
        changed
        |> Enum.flat_map(fn {id, {_record, affected}} ->
          Enum.map(affected, &%{advisory_id: id, package_id: &1.package_id})
        end)
        |> Enum.uniq()
    end)
  end

  defp sync_affected_releases(multi) do
    multi
    |> Multi.delete_all(:delete_affected_releases, fn %{changed_advisories: changed} ->
      from(r in "security_advisory_affected_releases",
        where: r.advisory_id in ^Map.keys(changed)
      )
    end)
    |> Multi.all(:load_releases, fn %{changed_advisories: changed} ->
      all_package_ids =
        changed
        |> Enum.flat_map(fn {_id, {_record, affected}} -> Enum.map(affected, & &1.package_id) end)
        |> Enum.uniq()

      from r in Hexpm.Repository.Release,
        where: r.package_id in ^all_package_ids,
        select: {r.id, r.package_id, r.version}
    end)
    |> Multi.insert_all(:insert_affected_releases, "security_advisory_affected_releases", fn
      %{changed_advisories: changed, load_releases: releases} ->
        releases_by_package = Enum.group_by(releases, &elem(&1, 1), &{elem(&1, 0), elem(&1, 2)})

        for {id, {_record, affected}} <- changed,
            %{package_id: package_id, requirements: requirements, versions: versions} <- affected,
            {release_id, version} <- Map.get(releases_by_package, package_id, []),
            Enum.any?(requirements, &Version.match?(version, &1)) or
              to_string(version) in versions,
            uniq: true,
            do: %{advisory_id: id, release_id: release_id}
    end)
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
