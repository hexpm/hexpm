defmodule Hexpm.Repository.RegistryBuilder do
  import Ecto.Query, only: [from: 2]
  require Hexpm.Repo
  require Logger
  alias Hexpm.Repository.{Package, Release, Repository, Requirement, Install}
  alias Hexpm.Repo

  @ets_table :hex_registry
  @version 4

  def full(repository) do
    locked_build(fn -> build_full(repository) end, 300_000)
  end

  # NOTE: Does not rebuild package indexes, use full/1 instead
  def v1_and_v2_repository(repository) do
    locked_build(fn -> build_v1_and_v2_repository(repository) end, 30_000)
  end

  def v1_repository(repository) do
    locked_build(fn -> build_v1_repository(repository) end, 30_000)
  end

  # NOTE: Does not rebuild package indexes, use full/1 instead
  def v2_repository(repository) do
    locked_build(fn -> build_v2_repository(repository) end, 30_000)
  end

  def v2_package(package) do
    build_v2_package(package)
  end

  def v2_package_delete(package) do
    delete_v2_package(package)
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

      ets = if repository.id == 1, do: build_ets(packages, releases, installs())
      new = build_new(repository, packages, releases)
      upload_files(repository, ets, new)

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

  defp build_v1_and_v2_repository(repository) do
    log(:repository, fn ->
      {packages, releases} = tuples(repository, nil)
      ets = if repository.id == 1, do: build_ets(packages, releases, installs())
      release_map = Map.new(releases)

      names = build_names(repository, packages)
      versions = build_versions(repository, packages, release_map)
      upload_files(repository, ets, {names, versions, []})

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        repository_cdn_key(repository, "registry-index")
      ])
    end)
  end

  defp build_v1_repository(%Repository{id: 1} = repository) do
    log(:v1_repository, fn ->
      {packages, releases} = tuples(repository, nil)
      ets = build_ets(packages, releases, installs())
      upload_files(repository, ets, nil)

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        repository_cdn_key(repository, "registry-index")
      ])
    end)
  end

  defp build_v1_repository(%Repository{}) do
    :ok
  end

  defp build_v2_repository(repository) do
    log(:v2_repository, fn ->
      {packages, releases} = tuples(repository, nil)
      release_map = Map.new(releases)

      names = build_names(repository, packages)
      versions = build_versions(repository, packages, release_map)
      upload_files(repository, nil, {names, versions, []})

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        repository_cdn_key(repository, "registry-index")
      ])
    end)
  end

  defp build_v2_package(package) do
    log(:v2_package_build, fn ->
      repository = package.repository

      {packages, releases} = tuples(repository, package)
      release_map = Map.new(releases)
      packages = build_packages(repository, packages, release_map)

      upload_files(repository, nil, {nil, nil, packages})

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-package-#{package.name}",
        repository_cdn_key(repository, "registry-package", package.name)
      ])
    end)
  end

  defp delete_v2_package(package) do
    log(:v2_package_delete, fn ->
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
        stacktrace = System.stacktrace()
        Logger.error("REGISTRY_BUILDER failed #{type}")
        reraise exception, stacktrace
    end
  end

  defp build_ets(packages, releases, installs) do
    tmp = Application.get_env(:hexpm, :tmp_dir)
    file = Path.join(tmp, "registry-#{:erlang.unique_integer([:positive])}.ets")

    tid = :ets.new(@ets_table, [:public])
    :ets.insert(tid, {:"$$version$$", @version})
    :ets.insert(tid, {:"$$installs2$$", installs})
    :ets.insert(tid, packages)
    :ets.insert(tid, trim_releases(releases))
    :ok = :ets.tab2file(tid, String.to_charlist(file))
    :ets.delete(tid)

    contents = File.read!(file) |> :zlib.gzip()
    signature = contents |> sign() |> Base.encode16(case: :lower)
    {contents, signature}
  end

  defp trim_releases(releases) do
    Enum.map(releases, fn {key, [deps, inner_checksum, _outer_checksum, tools, _retirement]} ->
      deps =
        Enum.map(deps, fn [_repo, dep, req, opt, app] ->
          [dep, req, opt, app]
        end)

      {key, [deps, Base.encode16(inner_checksum), tools]}
    end)
  end

  defp sign(contents) do
    key = Application.fetch_env!(:hexpm, :private_key)
    :hex_registry.sign(contents, key)
  end

  defp sign_protobuf(contents) do
    private_key = Application.fetch_env!(:hexpm, :private_key)
    :hex_registry.sign_protobuf(contents, private_key)
  end

  defp build_new(repository, packages, releases) do
    release_map = Map.new(releases)

    {
      build_names(repository, packages),
      build_versions(repository, packages, release_map),
      build_packages(repository, packages, release_map)
    }
  end

  defp build_names(repository, packages) do
    packages = Enum.map(packages, fn {name, _versions} -> %{name: name} end)

    %{packages: packages, repository: repository.name}
    |> :hex_registry.encode_names()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp build_versions(repository, packages, release_map) do
    packages =
      Enum.map(packages, fn {name, [versions]} ->
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
    Enum.map(packages, fn {name, [versions]} ->
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

  defp upload_files(repository, v1, v2) do
    upload_objects(v1_objects(v1, repository) ++ v2_objects(v2, repository))
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

  defp v1_objects(nil, _repository), do: []

  defp v1_objects({ets, signature}, repository) do
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

    index_meta = [{"signature", signature} | meta]
    opts = [cache_control: "public, max-age=600", meta: meta]
    index_opts = Keyword.put(opts, :meta, index_meta)

    ets_object = {repository_store_key(repository, "registry.ets.gz"), ets, index_opts}

    signature_object =
      {repository_store_key(repository, "registry.ets.gz.signed"), signature, opts}

    [ets_object, signature_object]
  end

  defp v2_objects(nil, _repository) do
    []
  end

  defp v2_objects({nil, nil, packages}, repository) do
    v2_package_objects(packages, repository)
  end

  defp v2_objects({names, versions, packages}, repository) do
    v2_index_objects(names, versions, repository) ++ v2_package_objects(packages, repository)
  end

  defp v2_index_objects(names, versions, repository) do
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

  defp v2_package_objects(packages, repository) do
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

  defp cache_control(%Repository{public: true}), do: "public, max-age=3600"
  defp cache_control(%Repository{public: false}), do: "private, max-age=3600"

  defp package_tuples(packages, releases) do
    Enum.reduce(releases, %{}, fn map, acc ->
      case Map.fetch(packages, map.package_id) do
        {:ok, package} -> Map.update(acc, package, [map.version], &[map.version | &1])
        :error -> acc
      end
    end)
    |> sort_package_tuples()
  end

  defp sort_package_tuples(tuples) do
    Enum.map(tuples, fn {name, versions} ->
      versions =
        versions
        |> Enum.sort(&(Version.compare(&1, &2) == :lt))
        |> Enum.map(&to_string/1)

      {name, [versions]}
    end)
    |> Enum.sort()
  end

  defp release_tuples(packages, releases, requirements) do
    Enum.flat_map(releases, fn map ->
      case Map.fetch(packages, map.package_id) do
        {:ok, package} ->
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
      select: {p.id, p.name}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp packages(_repository, package) do
    %{package.id => package.name}
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

  defp installs() do
    Install.all()
    |> Repo.all()
    |> Enum.map(&{&1.hex, &1.elixirs})
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
end
