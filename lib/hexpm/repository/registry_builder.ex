defmodule Hexpm.Repository.RegistryBuilder do
  @moduledoc """
  Builds the signed registry objects (`names`, `versions`, `packages/<name>`)
  and writes them to the repository bucket.

  Every builder returns the CDN purge the write calls for, as
  `%{keys: surrogate_keys, verify: targets}`, for the caller to hand to
  `Hexpm.CDN.purge/3`. Nothing here takes the `:registry` advisory lock or
  purges; `Hexpm.Repository.RegistryWorker` does both, so call these under
  that lock (or from a place where concurrent builds cannot happen, such as
  test setup).
  """

  import Ecto.Query, only: [from: 2]
  alias Hexpm.Repository.{Package, Release, Repository, Requirement, Storage}
  alias Hexpm.Repo

  @type purge :: %{keys: [String.t()], verify: [Hexpm.CDN.target()]}

  @doc """
  Rebuilds every registry object of the repository and removes package
  objects that no longer belong to a package.

  Verification covers `names` and `versions` only, not the tens of thousands
  of package objects a full build writes.
  """
  @spec full(Repository.t()) :: purge
  def full(repository) do
    {packages, releases} = tuples(repository, nil, requirements: true)

    new = build_all(repository, packages, releases)
    uploaded = upload_files(repository, new)

    {_, _, packages} = new

    new_keys =
      Enum.map(packages, &repository_store_key(repository, "packages/#{elem(&1, 0)}"))
      |> Enum.sort()

    old_keys =
      Hexpm.Store.list(:repo_bucket, repository_store_key(repository, "packages/"))
      |> Enum.sort()

    Hexpm.Store.delete_many(:repo_bucket, old_keys -- new_keys)

    index_uploads = Enum.filter(uploaded, &(&1.kind == :index))

    %{
      keys: ["registry", repository_cdn_key(repository, "registry")],
      verify: verify_targets(repository, index_uploads)
    }
  end

  @doc "Rebuilds `names` and `versions` for the repository, not the package objects."
  @spec repository(Repository.t()) :: purge
  def repository(repository) do
    {packages, releases} = tuples(repository, nil, requirements: false)
    release_map = Map.new(releases)

    names = build_names(repository, packages)
    versions = build_versions(repository, packages, release_map)
    uploaded = upload_files(repository, {names, versions, []})

    %{
      keys: ["registry-index", repository_cdn_key(repository, "registry-index")],
      verify: verify_targets(repository, uploaded)
    }
  end

  @doc "Rebuilds the `packages/<name>` object of the package."
  @spec package(Package.t()) :: purge
  def package(%Package{repository: repository} = package), do: packages(repository, [package])

  @doc """
  Rebuilds the `packages/<name>` objects of the packages, all in the given
  repository, with one round of queries and concurrent uploads.
  """
  @spec packages(Repository.t(), [Package.t()]) :: purge
  def packages(repository, packages) do
    {package_tuples, releases} = tuples(repository, packages, requirements: true)
    release_map = Map.new(releases)
    objects = build_packages(repository, package_tuples, release_map)

    uploaded = upload_files(repository, {nil, nil, objects})

    %{
      keys:
        Enum.flat_map(packages, fn package ->
          [
            "registry-package-#{package.name}",
            repository_cdn_key(repository, "registry-package", package.name)
          ]
        end),
      verify: verify_targets(repository, uploaded)
    }
  end

  @doc """
  Deletes the `packages/<name>` object. Takes the repository and the name
  rather than the package, which is usually gone by the time this runs.
  """
  @spec package_delete(Repository.t(), String.t()) :: purge
  def package_delete(repository, name) do
    key = repository_store_key(repository, "packages/#{name}")
    Storage.delete_object(key)

    %{
      keys: [
        "registry-package-#{name}",
        repository_cdn_key(repository, "registry-package", name)
      ],
      verify: verify_targets(repository, [%{key: key, etag: nil}])
    }
  end

  # The store key is the CDN path for both the public repository and the
  # `repos/<name>/` prefix of a private one; the check fetches the latter
  # with a token for that repository.
  defp verify_targets(%Repository{id: 1}, uploads) do
    Enum.map(uploads, fn %{key: key, etag: etag} ->
      %{url: Hexpm.Utils.cdn_url(key), etag: etag}
    end)
  end

  defp verify_targets(%Repository{name: name}, uploads) do
    Enum.map(uploads, fn %{key: key, etag: etag} ->
      %{url: Hexpm.Utils.cdn_url(key), etag: etag, repository: name}
    end)
  end

  # `packages` is nil for the whole repository or a list of packages in it.
  defp tuples(repository, packages, opts) do
    requirements =
      if Keyword.fetch!(opts, :requirements) do
        requirements(repository, packages)
      end

    releases = releases(repository, packages)
    packages = package_rows(repository, packages)
    package_tuples = package_tuples(packages, releases)
    release_tuples = release_tuples(packages, releases, requirements)

    {package_tuples, release_tuples}
  end

  defp build_all(repository, packages, releases) do
    release_map = Map.new(releases)

    {
      build_names(repository, packages),
      build_versions(repository, packages, release_map),
      build_packages(repository, packages, release_map)
    }
  end

  defp build_names(repository, packages) do
    packages =
      Enum.map(packages, fn {name, {updated_at, _versions, _advisories}} ->
        # Currently using Package.updated_at, would be more accurate to use
        # a timestamp that is only updated when the registry is updated by:
        # publish, revert, retire, or new advisory
        {seconds, nanos} = to_unix_nano(updated_at)

        %{
          name: name,
          updated_at: %{seconds: seconds, nanos: nanos}
        }
      end)

    %{packages: packages, repository: repository.name}
    |> :hex_registry.encode_names()
    |> Storage.sign_and_gzip()
  end

  defp build_versions(repository, packages, release_map) do
    packages =
      Enum.map(packages, fn {name, {_updated_at, [versions], _advisories}} ->
        %{
          name: name,
          versions: versions,
          retired: build_retired_indexes(name, versions, release_map),
          with_advisories: build_advisory_indexes(name, versions, release_map)
        }
      end)

    %{packages: packages, repository: repository.name}
    |> :hex_registry.encode_versions()
    |> Storage.sign_and_gzip()
  end

  defp build_retired_indexes(name, versions, release_map) do
    versions
    |> Enum.with_index()
    |> Enum.flat_map(fn {version, ix} ->
      [_deps, _inner_checksum, _outer_checksum, _tools, retirement, _advisory_ids, _inserted_at] =
        release_map[{name, version}]

      if retirement, do: [ix], else: []
    end)
  end

  defp build_advisory_indexes(name, versions, release_map) do
    versions
    |> Enum.with_index()
    |> Enum.flat_map(fn {version, ix} ->
      [_deps, _inner_checksum, _outer_checksum, _tools, _retirement, advisory_ids, _inserted_at] =
        release_map[{name, version}]

      if advisory_ids != [], do: [ix], else: []
    end)
  end

  defp build_packages(repository, packages, release_map) do
    Enum.map(packages, fn {name, {_updated_at, [versions], advisories}} ->
      contents = build_package(repository, name, versions, advisories, release_map)
      {name, contents}
    end)
  end

  defp build_package(repository, name, versions, package_advisories, release_map) do
    advisory_index =
      package_advisories
      |> Enum.with_index()
      |> Map.new(fn {a, i} -> {a["id"], i} end)

    releases =
      Enum.map(versions, fn version ->
        [deps, inner_checksum, outer_checksum, _tools, retirement, advisory_ids, inserted_at] =
          release_map[{name, version}]

        deps =
          Enum.map(deps, fn [repo, dep, req, opt, app] ->
            map = %{package: dep, requirement: req || ">= 0.0.0"}
            map = if opt, do: Map.put(map, :optional, true), else: map
            map = if app != dep, do: Map.put(map, :app, app), else: map
            map = if repository.name != repo, do: Map.put(map, :repository, repo), else: map
            map
          end)

        {published_seconds, published_nanos} = to_unix_nano(inserted_at)

        release = %{
          version: version,
          inner_checksum: inner_checksum,
          outer_checksum: outer_checksum,
          dependencies: deps,
          advisory_indexes: Enum.map(advisory_ids, &advisory_index[&1]),
          published_at: %{seconds: published_seconds, nanos: published_nanos}
        }

        if retirement do
          retire = %{reason: retirement_reason(retirement.reason)}

          retire =
            if retirement.message, do: Map.put(retire, :message, retirement.message), else: retire

          Map.put(release, :retired, retire)
        else
          release
        end
      end)

    %{
      name: name,
      repository: repository.name,
      releases: releases,
      advisories: Enum.map(package_advisories, &build_advisory/1)
    }
    |> :hex_registry.encode_package()
    |> Storage.sign_and_gzip()
  end

  defp build_advisory(%{
         "id" => id,
         "summary" => summary,
         "cvss_rating" => cvss_rating,
         "cvss_score" => cvss_score,
         "aliases" => aliases
       }) do
    map = %{
      id: id,
      summary: summary,
      html_url: "https://osv.dev/vulnerability/#{URI.encode(id)}",
      api_url: "https://api.osv.dev/v1/vulns/#{URI.encode(id)}",
      aliases: aliases
    }

    map = if cvss_score, do: Map.put(map, :cvss_score, cvss_score), else: map

    if cvss_rating do
      Map.put(map, :severity, advisory_severity(cvss_rating))
    else
      map
    end
  end

  defp advisory_severity("none"), do: :SEVERITY_NONE
  defp advisory_severity("low"), do: :SEVERITY_LOW
  defp advisory_severity("medium"), do: :SEVERITY_MEDIUM
  defp advisory_severity("high"), do: :SEVERITY_HIGH
  defp advisory_severity("critical"), do: :SEVERITY_CRITICAL

  defp retirement_reason("other"), do: :RETIRED_OTHER
  defp retirement_reason("invalid"), do: :RETIRED_INVALID
  defp retirement_reason("security"), do: :RETIRED_SECURITY
  defp retirement_reason("deprecated"), do: :RETIRED_DEPRECATED
  defp retirement_reason("renamed"), do: :RETIRED_RENAMED

  defp upload_files(repository, objects) do
    Task.async_stream(
      objects(objects, repository),
      fn {kind, key, data, surrogate_keys} ->
        etag = Storage.put_object(key, data, surrogate_keys, cache_control(repository))
        %{kind: kind, key: key, etag: etag}
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Enum.map(fn {:ok, upload} -> upload end)
  end

  defp objects(nil, _repository) do
    []
  end

  defp objects({nil, nil, packages}, repository) do
    package_objects(packages, repository)
  end

  defp objects({names, versions, packages}, repository) do
    index_objects(names, versions, repository) ++ package_objects(packages, repository)
  end

  defp index_objects(names, versions, repository) do
    surrogate_keys = [
      repository_cdn_key(repository, "registry"),
      repository_cdn_key(repository, "registry-index")
    ]

    [
      {:index, repository_store_key(repository, "names"), names, surrogate_keys},
      {:index, repository_store_key(repository, "versions"), versions, surrogate_keys}
    ]
  end

  defp package_objects(packages, repository) do
    Enum.map(packages, fn {name, contents} ->
      surrogate_keys = [
        repository_cdn_key(repository, "registry"),
        repository_cdn_key(repository, "registry-package", name)
      ]

      {:package, repository_store_key(repository, "packages/#{name}"), contents, surrogate_keys}
    end)
  end

  defp cache_control(%Repository{id: 1}), do: "public, max-age=3600"
  defp cache_control(%Repository{}), do: "private, max-age=3600"

  defp package_tuples(packages, releases) do
    Enum.reduce(releases, %{}, fn map, acc ->
      case Map.fetch(packages, map.package_id) do
        {:ok, {package, updated_at, advisories}} ->
          Map.update(
            acc,
            package,
            {updated_at, [map.version], advisories},
            fn {^updated_at, versions, ^advisories} ->
              {updated_at, [map.version | versions], advisories}
            end
          )

        :error ->
          acc
      end
    end)
    |> sort_package_tuples()
  end

  defp sort_package_tuples(tuples) do
    Enum.map(tuples, fn {name, {updated_at, versions, advisories}} ->
      versions =
        versions
        |> Enum.sort(&(Version.compare(&1, &2) == :lt))
        |> Enum.map(&to_string/1)

      {name, {updated_at, [versions], advisories}}
    end)
    |> Enum.sort()
  end

  defp release_tuples(packages, releases, requirements) do
    Enum.flat_map(releases, fn map ->
      case Map.fetch(packages, map.package_id) do
        {:ok, {package, _updated_at, _advisories}} ->
          key = {package, to_string(map.version)}
          deps = deps_list(requirements[map.release_id] || [])

          value = [
            deps,
            map.inner_checksum,
            map.outer_checksum,
            map.build_tools,
            map.retirement,
            map.advisory_ids,
            map.inserted_at
          ]

          [{key, value}]

        :error ->
          []
      end
    end)
  end

  defp deps_list(requirements) do
    Enum.map(requirements, fn map ->
      [map.repository, map.package, map.requirement, map.optional, map.app]
    end)
    |> Enum.sort()
  end

  defp package_rows(repository, packages) do
    query =
      from(p in Package,
        left_join: a in assoc(p, :security_advisories),
        on: is_nil(a.withdrawn_at),
        group_by: p.id,
        select:
          {p.id,
           {p.name, p.updated_at,
            fragment(
              "coalesce(json_agg(json_build_object('id', ?, 'summary', ?, 'cvss_rating', ?, 'cvss_score', ?, 'aliases', ?) ORDER BY ?) FILTER (WHERE ? IS NOT NULL), '[]')",
              a.id,
              a.summary,
              a.cvss_rating,
              a.cvss_score,
              a.aliases,
              a.id,
              a.id
            )}}
      )

    query =
      case packages do
        nil -> from(p in query, where: p.repository_id == ^repository.id)
        packages -> from(p in query, where: p.id in ^Enum.map(packages, & &1.id))
      end

    query
    |> Repo.all()
    |> Map.new()
  end

  defp releases(repository, packages) do
    from(
      r in Release,
      join: p in assoc(r, :package),
      left_join: a in assoc(r, :security_advisories),
      on: is_nil(a.withdrawn_at),
      group_by: r.id,
      select: %{
        release_id: r.id,
        version: r.version,
        package_id: r.package_id,
        inner_checksum: r.inner_checksum,
        outer_checksum: r.outer_checksum,
        build_tools: fragment("?->'build_tools'", r.meta),
        retirement: r.retirement,
        inserted_at: r.inserted_at,
        advisory_ids: fragment("array_remove(array_agg(?), NULL)", a.id)
      }
    )
    |> releases_where(repository, packages)
    |> Hexpm.Repo.all()
  end

  defp releases_where(query, repository, nil) do
    from(
      [r, p] in query,
      where: p.repository_id == ^repository.id
    )
  end

  defp releases_where(query, _repository, packages) do
    from(
      [r, p] in query,
      where: p.id in ^Enum.map(packages, & &1.id)
    )
  end

  defp requirements(repository, packages) do
    reqs =
      from(
        req in Requirement,
        join: rel in assoc(req, :release),
        join: parent in assoc(rel, :package),
        join: dep in assoc(req, :dependency),
        join: dep_repo in assoc(dep, :repository),
        select: %{
          release_id: req.release_id,
          repository: dep_repo.name,
          package: dep.name,
          app: req.app,
          requirement: req.requirement,
          optional: req.optional
        }
      )
      |> requirements_where(repository, packages)
      |> Repo.all()

    Enum.reduce(reqs, %{}, fn map, acc ->
      {release_id, map} = Map.pop(map, :release_id)
      Map.update(acc, release_id, [map], &[map | &1])
    end)
  end

  defp requirements_where(query, repository, nil) do
    from(
      [req, rel, parent] in query,
      where: parent.repository_id == ^repository.id
    )
  end

  defp requirements_where(query, _repository, packages) do
    from(
      [req, rel, parent] in query,
      where: parent.id in ^Enum.map(packages, & &1.id)
    )
  end

  defp repository_cdn_key(%Repository{id: 1}, key) do
    key
  end

  defp repository_cdn_key(%Repository{name: name}, key) do
    "#{key}/#{name}"
  end

  defp repository_cdn_key(%Repository{id: 1}, prefix, suffix) do
    "#{prefix}/#{suffix}"
  end

  defp repository_cdn_key(%Repository{name: name}, prefix, suffix) do
    "#{prefix}/#{name}/#{suffix}"
  end

  defp repository_store_key(%Repository{id: 1}, key) do
    key
  end

  defp repository_store_key(%Repository{name: name}, key) do
    "repos/#{name}/#{key}"
  end

  defp to_unix_nano(datetime) do
    unix = DateTime.to_unix(datetime, :nanosecond)
    {div(unix, 1_000_000_000), rem(unix, 1_000_000_000)}
  end
end
