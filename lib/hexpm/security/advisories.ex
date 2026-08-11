defmodule Hexpm.Security.Advisories do
  use Hexpm.Context

  import Ecto.Query

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.RegistryBuilder
  alias Hexpm.Repository.Repositories
  alias Hexpm.Repository.Repository
  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion

  @advisory_fields ~w(id summary aliases published_at modified_at withdrawn_at cvss_vector cvss_score cvss_rating)a

  def all(subject) do
    subject
    |> Advisory.all()
    |> where([a], is_nil(a.withdrawn_at))
    |> order_by([a], desc: a.published_at)
    |> Repo.all()
    |> Repo.preload([:references, :affected_versions])
  end

  def group_for_display(advisories) when is_list(advisories) do
    groups = Enum.group_by(advisories, &display_group_key/1)

    advisories
    |> Enum.map(&display_group_key/1)
    |> Enum.uniq()
    |> Enum.map(fn key -> merge_display_group(Map.fetch!(groups, key)) end)
  end

  def policy_suggestions(%Repository{} = repository, term, limit) do
    if is_binary(term) and String.valid?(term) do
      group_keys = policy_advisory_group_keys(repository, term, limit)

      repository
      |> policy_advisories(group_keys)
      |> policy_suggestion_items(repository)
      |> Enum.filter(&policy_suggestion_matches?(&1, term))
      |> Enum.take(limit)
      |> Enum.map(&Map.take(&1, [:identifier, :summary, :package, :requirements]))
    else
      []
    end
  end

  def valid_policy_exception?(repository_name, package, identifier)
      when is_binary(repository_name) and is_binary(package) and is_binary(identifier) do
    if String.valid?(repository_name) and String.valid?(package) and String.valid?(identifier) do
      case Repositories.get(repository_name) do
        nil ->
          false

        repository ->
          identifier = identifier |> String.trim() |> String.downcase()

          repository
          |> policy_advisory_scope()
          |> where(
            [a, _ap, p],
            p.name == ^package and
              fragment(
                "(lower(?) = ? OR EXISTS (SELECT 1 FROM unnest(?) AS alias WHERE lower(alias) = ?))",
                a.id,
                ^identifier,
                a.aliases,
                ^identifier
              )
          )
          |> Repo.exists?()
      end
    else
      false
    end
  end

  def valid_policy_exception?(_repository_name, _package, _identifier), do: false

  defp policy_suggestion_items(advisories, repository) do
    grouped = Enum.group_by(advisories, &display_group_key/1)

    advisories
    |> Enum.map(&display_group_key/1)
    |> Enum.uniq()
    |> Enum.map(fn key ->
      {merge_display_group(Map.fetch!(grouped, key)), Map.fetch!(grouped, key)}
    end)
    |> Enum.flat_map(fn {advisory, group} ->
      identifiers = group |> Enum.flat_map(&display_identifiers/1) |> Enum.uniq()
      identifier = preferred_identifier(identifiers, advisory.id)
      summaries = group |> Enum.map(& &1.summary) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      group
      |> Enum.flat_map(&policy_affected_requirements(&1, repository.id))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {package, requirements} ->
        requirements = requirements |> Enum.uniq() |> Enum.sort()

        %{
          identifier: identifier,
          identifiers: identifiers,
          summary: advisory.summary,
          summaries: summaries,
          package: package,
          requirements: requirements
        }
      end)
    end)
    |> Enum.uniq_by(&{&1.identifier, &1.package})
    |> Enum.sort_by(&{&1.identifier, &1.package})
  end

  defp policy_advisory_group_keys(repository, term, limit) do
    term = term |> to_string() |> String.trim() |> String.downcase()

    query =
      repository
      |> policy_advisory_scope()

    query =
      if term == "" do
        query
      else
        where(
          query,
          [a, _ap, p],
          fragment("strpos(lower(?), ?) > 0", a.id, ^term) or
            fragment("strpos(lower(?), ?) > 0", a.summary, ^term) or
            fragment("strpos(lower(?), ?) > 0", p.name, ^term) or
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS alias WHERE strpos(lower(alias), ?) > 0)",
              a.aliases,
              ^term
            )
        )
      end

    query
    |> select(
      [a],
      fragment(
        "CASE WHEN ? LIKE 'CVE-%' THEN ? ELSE COALESCE((SELECT alias FROM unnest(?) WITH ORDINALITY AS aliases(alias, position) WHERE alias LIKE 'CVE-%' ORDER BY position LIMIT 1), ?) END",
        a.id,
        a.id,
        a.aliases,
        a.id
      )
    )
    |> distinct(true)
    |> order_by(
      [a],
      asc:
        fragment(
          "CASE WHEN ? LIKE 'CVE-%' THEN ? ELSE COALESCE((SELECT alias FROM unnest(?) WITH ORDINALITY AS aliases(alias, position) WHERE alias LIKE 'CVE-%' ORDER BY position LIMIT 1), ?) END",
          a.id,
          a.id,
          a.aliases,
          a.id
        )
    )
    |> limit(^limit)
    |> Repo.all()
  end

  defp policy_advisories(_repository, []), do: []

  defp policy_advisories(repository, group_keys) do
    repository
    |> policy_advisory_scope()
    |> where(
      [a],
      a.id in ^group_keys or
        fragment("? && ?", a.aliases, type(^group_keys, {:array, :string}))
    )
    |> distinct(true)
    |> Repo.all()
    |> Enum.filter(&(display_group_key(&1) in group_keys))
    |> Repo.preload(affected_versions: :package, affected_releases: :package)
  end

  defp policy_advisory_scope(repository) do
    from(a in Advisory,
      join: ap in "security_advisory_affected_packages",
      on: ap.advisory_id == a.id,
      join: p in Package,
      on: p.id == ap.package_id,
      where: p.repository_id == ^repository.id and is_nil(a.withdrawn_at)
    )
  end

  defp policy_affected_requirements(advisory, repository_id) do
    affected_versions =
      advisory.affected_versions
      |> loaded_assoc()
      |> Enum.filter(&(&1.package.repository_id == repository_id))

    ranges =
      affected_versions
      |> Enum.map(&{&1.package.name, to_string(&1.requirement)})

    versions =
      advisory.affected_releases
      |> loaded_assoc()
      |> Enum.filter(&(&1.package.repository_id == repository_id))
      |> Enum.reject(fn release ->
        Enum.any?(affected_versions, fn affected_version ->
          affected_version.package_id == release.package_id and
            Version.match?(release.version, affected_version.requirement)
        end)
      end)
      |> Enum.map(&{&1.package.name, "== #{&1.version}"})

    ranges ++ versions
  end

  defp policy_suggestion_matches?(_item, term) when term in [nil, ""], do: true

  defp policy_suggestion_matches?(item, term) do
    term = term |> to_string() |> String.trim() |> String.downcase()

    Enum.any?(
      item.identifiers ++ item.summaries ++ [item.package],
      &String.contains?(String.downcase(&1), term)
    )
  end

  defp preferred_identifier(identifiers, fallback) do
    Enum.find(identifiers, &String.starts_with?(String.upcase(&1), "CVE-")) || fallback
  end

  def upsert(records, package_ids) do
    Multi.new()
    |> upsert_advisories(records)
    |> prepare_changed(package_ids)
    |> sync_references()
    |> sync_affected_versions()
    |> sync_affected_packages()
    |> sync_affected_releases()
    |> reconcile_advisories(records)
    |> rebuild_package_registries()
    |> Repo.transaction(timeout: 60_000)
    |> rebuild_repository_registries()
  end

  defp upsert_advisories(multi, records) do
    Multi.run(multi, :upsert_advisories, fn repo, _ ->
      with {:ok, rows} <- advisory_rows(records) do
        # published_at is set on initial insert only — it's the date the
        # advisory was first published and is treated as immutable, even if
        # the feed revises it on a later sync.
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

  defp merge_display_group(advisories) do
    primary = Enum.min_by(advisories, &source_key/1)

    advisories =
      [primary | Enum.reject(advisories, &(&1.id == primary.id))]

    %{
      primary
      | aliases: display_aliases(primary, advisories),
        published_at: min_datetime_field(advisories, :published_at),
        modified_at: max_datetime_field(advisories, :modified_at),
        references: uniq_references(advisories),
        affected_versions: uniq_affected_versions(advisories)
    }
  end

  defp display_aliases(primary, advisories) do
    advisory_ids = MapSet.new(advisories, & &1.id)

    advisories
    |> Enum.flat_map(&display_identifiers/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == primary.id))
    |> Enum.map(fn id ->
      if MapSet.member?(advisory_ids, id) do
        %{id: id, url: "https://osv.dev/vulnerability/#{URI.encode(id)}"}
      else
        %{id: id, url: nil}
      end
    end)
  end

  defp display_group_key(advisory) do
    Enum.find(display_identifiers(advisory), &String.starts_with?(&1, "CVE-")) || advisory.id
  end

  defp display_identifiers(advisory) do
    [advisory.id | advisory.aliases || []]
    |> Enum.reject(&is_nil/1)
  end

  defp source_priority("EEF-" <> _), do: 0
  defp source_priority("GHSA-" <> _), do: 1
  defp source_priority("NVD-" <> _), do: 2
  defp source_priority(_), do: 3

  defp source_key(advisory), do: {source_priority(advisory.id), advisory.id}

  defp min_datetime_field(advisories, field) do
    advisories
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp max_datetime_field(advisories, field) do
    advisories
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp uniq_references(advisories) do
    advisories
    |> Enum.flat_map(&loaded_assoc(&1.references))
    |> Enum.group_by(& &1.url)
    |> Enum.map(fn {url, refs} ->
      types = refs |> Enum.map(& &1.type) |> Enum.uniq()
      %{url: url, types: types}
    end)
  end

  defp uniq_affected_versions(advisories) do
    advisories
    |> Enum.flat_map(&loaded_assoc(&1.affected_versions))
    |> Enum.uniq_by(&{&1.package_id, to_string(&1.requirement)})
  end

  defp loaded_assoc(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_assoc(nil), do: []
  defp loaded_assoc(values), do: values

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

  defp rebuild_package_registries(multi) do
    Multi.run(multi, :rebuild_package_registries, fn
      repo, %{upsert_advisories: changed, reconcile: {_count, reconciled_package_ids}} ->
        advisory_ids = Map.keys(changed)

        upserted_packages =
          repo.all(
            from p in Package,
              join: ap in "security_advisory_affected_packages",
              on: ap.package_id == p.id,
              where: ap.advisory_id in ^advisory_ids,
              distinct: true,
              preload: [:repository]
          )

        reconciled_packages =
          repo.all(
            from p in Package,
              where: p.id in ^reconciled_package_ids,
              preload: [:repository]
          )

        packages = Enum.uniq_by(upserted_packages ++ reconciled_packages, & &1.id)
        Enum.each(packages, &RegistryBuilder.package/1)
        {:ok, packages}
    end)
  end

  defp rebuild_repository_registries({:ok, %{rebuild_package_registries: packages}} = result) do
    metadata = Logger.metadata()

    repositories =
      packages
      |> Enum.map(& &1.repository)
      |> Enum.uniq_by(& &1.id)

    Hexpm.Tasks
    |> Task.Supervisor.async_stream_nolink(repositories, fn repository ->
      Logger.metadata(metadata)
      RegistryBuilder.repository(repository)
    end)
    |> Stream.run()

    result
  end

  defp rebuild_repository_registries(result), do: result

  defp reconcile_advisories(multi, records) do
    seen_ids = Enum.map(records, & &1.id)

    Multi.run(multi, :reconcile, fn repo, _changes ->
      {count, rows} =
        repo.delete_all(
          from(a in Advisory,
            where: a.id not in ^seen_ids,
            join: p in "security_advisory_affected_packages",
            on: p.advisory_id == a.id,
            select: p.package_id
          )
        )

      {:ok, {count, rows}}
    end)
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
