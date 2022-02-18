defmodule Hexpm.Repository.RegistryBuilder do
  import Ecto.Query, only: [from: 2]
  require Hexpm.Repo
  require Logger
  alias Hexpm.Repository.{Package, Release, Repository, Requirement}
  alias Hexpm.Repo

  def full(repository) do
    locked_build(fn -> build_full(repository) end, 300_000)
  end

  # NOTE: Does not rebuild package indexes, use full/1 instead
  def repository(repository) do
    locked_build(fn -> build_partial(repository) end, 30_000)
  end

  def package(package) do
    build_package(package)
  end

  def package_delete(package) do
    delete_package(package)
  end

  defp locked_build(fun, timeout) do
    start_time = System.monotonic_time(:millisecond)
    lock(fun, start_time, timeout)
  end

  defp lock(fun, start_time, timeout) do
    now = System.monotonic_time(:millisecond)

    if now > start_time + timeout do
      raise "lock timeout"
    end

    {:ok, ran?} =
      Repo.transaction(
        fn -> run_with_lock(fun, now - start_time) end,
        timeout: timeout
      )

    unless ran? do
      Process.sleep(1000)
      lock(fun, start_time, timeout)
    end
  end

  if Mix.env() == :test do
    defp run_with_lock(fun, time) do
      if Repo.try_advisory_lock?(:registry) do
        try do
          Logger.warn("REGISTRY_BUILDER aquired_lock (#{time}ms)")
          fun.()
          true
        after
          Repo.advisory_unlock(:registry)
        end
      else
        Logger.warn("REGISTRY_BUILDER failed_aquire_lock (#{time}ms)")
        false
      end
    end
  else
    defp run_with_lock(fun, time) do
      if Repo.try_advisory_xact_lock?(:registry) do
        Logger.warn("REGISTRY_BUILDER aquired_lock (#{time}ms)")
        fun.()
        true
      else
        Logger.warn("REGISTRY_BUILDER failed_aquire_lock (#{time}ms)")
        false
      end
    end
  end

  defp build_full(repository) do
    log(:all, fn ->
      {packages, releases} = tuples(repository, nil)

      new = build_all(repository, packages, releases)
      upload_files(repository, new)

      {_, _, packages} = new

      new_keys =
        Enum.map(packages, &repository_store_key(repository, "packages/#{elem(&1, 0)}"))
        |> Enum.sort()

      old_keys =
        Hexpm.Store.list(:repo_bucket, repository_store_key(repository, "packages/"))
        |> Enum.sort()

      Hexpm.Store.delete_many(:repo_bucket, old_keys -- new_keys)

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry",
        repository_cdn_key(repository, "registry")
      ])
    end)
  end

  defp build_partial(repository) do
    log(:repository, fn ->
      {packages, releases} = tuples(repository, nil)
      release_map = Map.new(releases)

      names = build_names(repository, packages)
      versions = build_versions(repository, packages, release_map)
      upload_files(repository, {names, versions, []})

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        repository_cdn_key(repository, "registry-index")
      ])
    end)
  end

  defp build_package(package) do
    log(:package_build, fn ->
      repository = package.repository

      {packages, releases} = tuples(repository, package)
      release_map = Map.new(releases)
      packages = build_packages(repository, packages, release_map)

      upload_files(repository, {nil, nil, packages})

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-package-#{package.name}",
        repository_cdn_key(repository, "registry-package", package.name)
      ])
    end)
  end

  defp delete_package(package) do
    log(:package_delete, fn ->
      repository = package.repository

      Hexpm.Store.delete(
        :repo_bucket,
        repository_store_key(repository, "packages/#{package.name}")
      )

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-package-#{package.name}",
        repository_cdn_key(repository, "registry-package", package.name)
      ])
    end)
  end

  defp tuples(repository, package) do
    requirements = requirements(repository, package)
    releases = releases(repository, package)
    packages = packages(repository, package)
    package_tuples = package_tuples(packages, releases)
    release_tuples = release_tuples(packages, releases, requirements)

    {package_tuples, release_tuples}
  end

  defp log(type, fun) do
    try do
      {time, _} = :timer.tc(fun)
      Logger.warn("REGISTRY_BUILDER completed #{type} (#{div(time, 1000)}ms)")
    catch
      exception ->
        Logger.error("REGISTRY_BUILDER failed #{type}")
        reraise exception, __STACKTRACE__
    end
  end

  defp sign_protobuf(contents) do
    private_key = Application.fetch_env!(:hexpm, :private_key)
    :hex_registry.sign_protobuf(contents, private_key)
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
      Enum.map(packages, fn {name, {updated_at, _versions}} ->
        # Currently using Package.updated_at, would be more accurate to use
        # a timestamp that is only updated when the registry is updated by:
        # publish, revert, or retire
        {seconds, nanos} = to_unix_nano(updated_at)

        %{
          name: name,
          updated_at: %{seconds: seconds, nanos: nanos}
        }
      end)

    %{packages: packages, repository: repository.name}
    |> :hex_registry.encode_names()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp build_versions(repository, packages, release_map) do
    packages =
      Enum.map(packages, fn {name, {_updated_at, [versions]}} ->
        %{
          name: name,
          versions: versions,
          retired: build_retired_indexes(name, versions, release_map)
        }
      end)

    %{packages: packages, repository: repository.name}
    |> :hex_registry.encode_versions()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp build_retired_indexes(name, versions, release_map) do
    versions
    |> Enum.with_index()
    |> Enum.flat_map(fn {version, ix} ->
      [_deps, _inner_checksum, _outer_checksum, _tools, retirement] = release_map[{name, version}]
      if retirement, do: [ix], else: []
    end)
  end

  defp build_packages(repository, packages, release_map) do
    Enum.map(packages, fn {name, {_updated_at, [versions]}} ->
      contents = build_package(repository, name, versions, release_map)
      {name, contents}
    end)
  end

  defp build_package(repository, name, versions, release_map) do
    releases =
      Enum.map(versions, fn version ->
        [deps, inner_checksum, outer_checksum, _tools, retirement] = release_map[{name, version}]

        deps =
          Enum.map(deps, fn [repo, dep, req, opt, app] ->
            map = %{package: dep, requirement: req || ">= 0.0.0"}
            map = if opt, do: Map.put(map, :optional, true), else: map
            map = if app != dep, do: Map.put(map, :app, app), else: map
            map = if repository.name != repo, do: Map.put(map, :repository, repo), else: map
            map
          end)

        release = %{
          version: version,
          inner_checksum: inner_checksum,
          outer_checksum: outer_checksum,
          dependencies: deps
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
      releases: releases
    }
    |> :hex_registry.encode_package()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp retirement_reason("other"), do: :RETIRED_OTHER
  defp retirement_reason("invalid"), do: :RETIRED_INVALID
  defp retirement_reason("security"), do: :RETIRED_SECURITY
  defp retirement_reason("deprecated"), do: :RETIRED_DEPRECATED
  defp retirement_reason("renamed"), do: :RETIRED_RENAMED

  defp upload_files(repository, objects) do
    upload_objects(objects(objects, repository))
  end

  defp upload_objects(objects) do
    Task.async_stream(
      objects,
      fn {key, data, opts} ->
        Hexpm.Store.put(:repo_bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Stream.run()
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
    surrogate_key =
      Enum.join(
        [
          repository_cdn_key(repository, "registry"),
          repository_cdn_key(repository, "registry-index")
        ],
        " "
      )

    meta = [
      {"surrogate-key", surrogate_key},
      {"surrogate-control", "public, max-age=604800"}
    ]

    opts = [cache_control: cache_control(repository), meta: meta]
    index_opts = Keyword.put(opts, :meta, meta)

    names_object = {repository_store_key(repository, "names"), names, index_opts}
    versions_object = {repository_store_key(repository, "versions"), versions, index_opts}

    [names_object, versions_object]
  end

  defp package_objects(packages, repository) do
    Enum.map(packages, fn {name, contents} ->
      surrogate_key =
        Enum.join(
          [
            repository_cdn_key(repository, "registry"),
            repository_cdn_key(repository, "registry-package", name)
          ],
          " "
        )

      meta = [
        {"surrogate-key", surrogate_key},
        {"surrogate-control", "public, max-age=604800"}
      ]

      opts = [cache_control: cache_control(repository), meta: meta]
      {repository_store_key(repository, "packages/#{name}"), contents, opts}
    end)
  end

  defp cache_control(%Repository{id: 1}), do: "public, max-age=3600"
  defp cache_control(%Repository{}), do: "private, max-age=3600"

  defp package_tuples(packages, releases) do
    Enum.reduce(releases, %{}, fn map, acc ->
      case Map.fetch(packages, map.package_id) do
        {:ok, {package, updated_at}} ->
          Map.update(acc, package, {updated_at, [map.version]}, fn {^updated_at, versions} ->
            {updated_at, [map.version | versions]}
          end)

        :error ->
          acc
      end
    end)
    |> sort_package_tuples()
  end

  defp sort_package_tuples(tuples) do
    Enum.map(tuples, fn {name, {updated_at, versions}} ->
      versions =
        versions
        |> Enum.sort(&(Version.compare(&1, &2) == :lt))
        |> Enum.map(&to_string/1)

      {name, {updated_at, [versions]}}
    end)
    |> Enum.sort()
  end

  defp release_tuples(packages, releases, requirements) do
    Enum.flat_map(releases, fn map ->
      case Map.fetch(packages, map.package_id) do
        {:ok, {package, _updated_at}} ->
          key = {package, to_string(map.version)}
          deps = deps_list(requirements[map.release_id] || [])
          value = [deps, map.inner_checksum, map.outer_checksum, map.build_tools, map.retirement]
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

  defp packages(repository, nil) do
    from(
      p in Package,
      where: p.repository_id == ^repository.id,
      select: {p.id, {p.name, p.updated_at}}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp packages(_repository, package) do
    %{package.id => {package.name, package.updated_at}}
  end

  defp releases(repository, package) do
    from(
      r in Release,
      join: p in assoc(r, :package),
      select: %{
        release_id: r.id,
        version: r.version,
        package_id: r.package_id,
        inner_checksum: r.inner_checksum,
        outer_checksum: r.outer_checksum,
        build_tools: fragment("?->'build_tools'", r.meta),
        retirement: r.retirement
      }
    )
    |> releases_where(repository, package)
    |> Hexpm.Repo.all()
  end

  defp releases_where(query, repository, nil) do
    from(
      [r, p] in query,
      where: p.repository_id == ^repository.id
    )
  end

  defp releases_where(query, _repository, package) do
    from(
      [r, p] in query,
      where: p.id == ^package.id
    )
  end

  defp requirements(repository, package) do
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
      |> requirements_where(repository, package)
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

  defp requirements_where(query, _repository, package) do
    from(
      [req, rel, parent] in query,
      where: parent.id == ^package.id
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
