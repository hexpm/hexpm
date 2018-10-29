defmodule Hexpm.Repository.RegistryBuilder do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  import Ecto.Query, only: [from: 2]
  require Hexpm.Repo
  require Logger
  alias Hexpm.Accounts.Organization
  alias Hexpm.Repository.{Package, Release, Requirement, Install}
  alias Hexpm.Repo

  @ets_table :hex_registry
  @version 4
  @lock_timeout 30_000
  @transaction_timeout 60_000

  def full_build(organization) do
    locked_build(fn -> full(organization) end)
  end

  def partial_build(action) do
    locked_build(fn -> partial(action) end)
  end

  defp locked_build(fun) do
    Repo.transaction(
      fn ->
        Repo.advisory_lock(:registry, timeout: @lock_timeout)
        fun.()
        Repo.advisory_unlock(:registry)
      end,
      timeout: @transaction_timeout
    )
  end

  defp full(organization) do
    log(:full, fn ->
      {packages, releases, installs} = tuples(organization)

      ets = if organization.id == 1, do: build_ets(packages, releases, installs)
      new = build_new(organization, packages, releases)
      upload_files(organization, ets, new)

      {_, _, packages} = new

      new_keys =
        Enum.map(packages, &organization_store_key(organization, "packages/#{elem(&1, 0)}"))
        |> Enum.sort()

      old_keys =
        Hexpm.Store.list(nil, :s3_bucket, organization_store_key(organization, "packages/"))
        |> Enum.sort()

      Hexpm.Store.delete_many(nil, :s3_bucket, old_keys -- new_keys)

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry",
        organization_cdn_key(organization, "registry")
      ])
    end)
  end

  defp partial({:v1, %Organization{id: 1} = organization}) do
    log(:v1, fn ->
      {packages, releases, installs} = tuples(organization)
      ets = build_ets(packages, releases, installs)
      upload_files(organization, ets, nil)

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        organization_cdn_key(organization, "registry-index")
      ])
    end)
  end

  defp partial({:publish, package}) do
    log(:publish, fn ->
      package_name = package.name
      organization = package.organization
      {packages, releases, installs} = tuples(organization)
      release_map = Map.new(releases)

      ets = if organization.id == 1, do: build_ets(packages, releases, installs)
      names = build_names(packages)
      versions = build_versions(packages, release_map)

      case Enum.find(packages, &match?({^package_name, _}, &1)) do
        {^package_name, [package_versions]} ->
          package_object =
            build_package(organization, package_name, package_versions, release_map)

          upload_files(organization, ets, {names, versions, [{package_name, package_object}]})

        nil ->
          upload_files(organization, ets, {names, versions, []})

          Hexpm.Store.delete(
            nil,
            :s3_bucket,
            organization_store_key(organization, "packages/#{package_name}")
          )
      end

      Hexpm.CDN.purge_key(:fastly_hexrepo, [
        "registry-index",
        "registry-package-#{package_name}",
        organization_cdn_key(organization, "registry-index"),
        organization_cdn_key(organization, "registry-package", package_name)
      ])
    end)
  end

  defp tuples(organization) do
    installs = installs(organization)
    requirements = requirements(organization)
    releases = releases(organization)
    packages = packages(organization)
    package_tuples = package_tuples(packages, releases)
    release_tuples = release_tuples(packages, releases, requirements)

    {package_tuples, release_tuples, installs}
  end

  defp log(type, fun) do
    try do
      {time, _} = :timer.tc(fun)
      Logger.warn("REGISTRY_BUILDER_COMPLETED #{type} (#{div(time, 1000)}ms)")
    catch
      exception ->
        stacktrace = System.stacktrace()
        Logger.error("REGISTRY_BUILDER_FAILED #{type}")
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
    Enum.map(releases, fn {key, [deps, checksum, tools, _retirement]} ->
      deps =
        Enum.map(deps, fn [_repo, dep, req, opt, app] ->
          [dep, req, opt, app]
        end)

      {key, [deps, checksum, tools]}
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

  defp build_new(organization, packages, releases) do
    release_map = Map.new(releases)

    {
      build_names(packages),
      build_versions(packages, release_map),
      build_packages(organization, packages, release_map)
    }
  end

  defp build_names(packages) do
    packages = Enum.map(packages, fn {name, _versions} -> %{name: name} end)

    %{packages: packages}
    |> :hex_registry.encode_names()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp build_versions(packages, release_map) do
    packages =
      Enum.map(packages, fn {name, [versions]} ->
        %{
          name: name,
          versions: versions,
          retired: build_retired_indexes(name, versions, release_map)
        }
      end)

    %{packages: packages}
    |> :hex_registry.encode_versions()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp build_retired_indexes(name, versions, release_map) do
    versions
    |> Enum.with_index()
    |> Enum.flat_map(fn {version, ix} ->
      [_deps, _checksum, _tools, retirement] = release_map[{name, version}]
      if retirement, do: [ix], else: []
    end)
  end

  defp build_packages(organization, packages, release_map) do
    Enum.map(packages, fn {name, [versions]} ->
      contents = build_package(organization, name, versions, release_map)
      {name, contents}
    end)
  end

  defp build_package(organization, name, versions, release_map) do
    releases =
      Enum.map(versions, fn version ->
        [deps, checksum, _tools, retirement] = release_map[{name, version}]

        deps =
          Enum.map(deps, fn [repo, dep, req, opt, app] ->
            map = %{package: dep, requirement: req || ">= 0.0.0"}
            map = if opt, do: Map.put(map, :optional, true), else: map
            map = if app != dep, do: Map.put(map, :app, app), else: map
            map = if organization.name != repo, do: Map.put(map, :repository, repo), else: map
            map
          end)

        release = %{
          version: version,
          checksum: Base.decode16!(checksum),
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

    %{releases: releases}
    |> :hex_registry.encode_package()
    |> sign_protobuf()
    |> :zlib.gzip()
  end

  defp retirement_reason("other"), do: :RETIRED_OTHER
  defp retirement_reason("invalid"), do: :RETIRED_INVALID
  defp retirement_reason("security"), do: :RETIRED_SECURITY
  defp retirement_reason("deprecated"), do: :RETIRED_DEPRECATED
  defp retirement_reason("renamed"), do: :RETIRED_RENAMED

  defp upload_files(organization, v1, v2) do
    (v2_objects(v2, organization) ++ v1_objects(v1, organization))
    |> Task.async_stream(
      fn {key, data, opts} ->
        Hexpm.Store.put(nil, :s3_bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Stream.run()
  end

  defp v1_objects(nil, _organization), do: []

  defp v1_objects({ets, signature}, organization) do
    surrogate_key =
      organization_cdn_key(organization, "registry") <>
        " " <> organization_cdn_key(organization, "registry-index")

    meta = [
      {"surrogate-key", surrogate_key},
      {"surrogate-control", "public, max-age=604800"}
    ]

    index_meta = [{"signature", signature} | meta]
    opts = [cache_control: "public, max-age=600", meta: meta]
    index_opts = Keyword.put(opts, :meta, index_meta)

    ets_object = {organization_store_key(organization, "registry.ets.gz"), ets, index_opts}

    signature_object =
      {organization_store_key(organization, "registry.ets.gz.signed"), signature, opts}

    [ets_object, signature_object]
  end

  defp v2_objects(nil, _organization), do: []

  defp v2_objects({names, versions, packages}, organization) do
    surrogate_key =
      organization_cdn_key(organization, "registry") <>
        " " <> organization_cdn_key(organization, "registry-index")

    meta = [
      {"surrogate-key", surrogate_key},
      {"surrogate-control", "public, max-age=604800"}
    ]

    opts = [cache_control: cache_control(organization), meta: meta]
    index_opts = Keyword.put(opts, :meta, meta)

    names_object = {organization_store_key(organization, "names"), names, index_opts}
    versions_object = {organization_store_key(organization, "versions"), versions, index_opts}

    package_objects =
      Enum.map(packages, fn {name, contents} ->
        surrogate_key =
          organization_cdn_key(organization, "registry") <>
            " " <> organization_cdn_key(organization, "registry-package", name)

        meta = [
          {"surrogate-key", surrogate_key},
          {"surrogate-control", "public, max-age=604800"}
        ]

        opts = Keyword.put(opts, :meta, meta)
        {organization_store_key(organization, "packages/#{name}"), contents, opts}
      end)

    package_objects ++ [names_object, versions_object]
  end

  defp cache_control(%Organization{id: 1}), do: "public, max-age=3600"
  defp cache_control(%Organization{}), do: "private, max-age=3600"

  defp package_tuples(packages, releases) do
    Enum.reduce(releases, %{}, fn {_, vsn, pkg_id, _, _, _}, map ->
      case Map.fetch(packages, pkg_id) do
        {:ok, package} -> Map.update(map, package, [vsn], &[vsn | &1])
        :error -> map
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
    Enum.flat_map(releases, fn {id, version, pkg_id, checksum, tools, retirement} ->
      case Map.fetch(packages, pkg_id) do
        {:ok, package} ->
          deps = deps_list(requirements[id] || [])
          [{{package, to_string(version)}, [deps, checksum, tools, retirement]}]

        :error ->
          []
      end
    end)
  end

  defp deps_list(requirements) do
    Enum.map(requirements, fn {repo, dep_name, app, req, opt} ->
      [repo, dep_name, req, opt, app]
    end)
    |> Enum.sort()
  end

  defp packages(organization) do
    from(
      p in Package,
      where: p.organization_id == ^organization.id,
      select: {p.id, p.name}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp releases(organization) do
    from(
      r in Release,
      join: p in assoc(r, :package),
      where: p.organization_id == ^organization.id,
      select: {
        r.id,
        r.version,
        r.package_id,
        r.checksum,
        fragment("?->'build_tools'", r.meta),
        r.retirement
      }
    )
    |> Hexpm.Repo.all()
  end

  defp requirements(organization) do
    reqs =
      from(
        req in Requirement,
        join: rel in assoc(req, :release),
        join: parent in assoc(rel, :package),
        join: dep in assoc(req, :dependency),
        join: dep_repo in assoc(dep, :organization),
        where: parent.organization_id == ^organization.id,
        select: {
          req.release_id,
          dep_repo.name,
          dep.name,
          req.app,
          req.requirement,
          req.optional
        }
      )
      |> Repo.all()

    Enum.reduce(reqs, %{}, fn {rel_id, repo, dep_name, app, req, opt}, map ->
      tuple = {repo, dep_name, app, req, opt}
      Map.update(map, rel_id, [tuple], &[tuple | &1])
    end)
  end

  defp installs(%Organization{id: 1}) do
    Install.all()
    |> Repo.all()
    |> Enum.map(&{&1.hex, &1.elixirs})
  end

  defp installs(%Organization{}) do
    []
  end

  defp organization_cdn_key(%Organization{id: 1}, key) do
    key
  end

  defp organization_cdn_key(%Organization{name: name}, key) do
    "#{key}/#{name}"
  end

  defp organization_cdn_key(%Organization{id: 1}, prefix, suffix) do
    "#{prefix}/#{suffix}"
  end

  defp organization_cdn_key(%Organization{name: name}, prefix, suffix) do
    "#{prefix}/#{name}/#{suffix}"
  end

  defp organization_store_key(%Organization{id: 1}, key) do
    key
  end

  defp organization_store_key(%Organization{name: name}, key) do
    "repos/#{name}/#{key}"
  end
end
