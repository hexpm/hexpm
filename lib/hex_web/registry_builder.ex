defmodule HexWeb.RegistryBuilder do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  # TODO: installs ???
  # TODO: signing
  # TODO: partial builds

  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  require Logger
  alias Ecto.Adapters.SQL
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Requirement
  alias HexWeb.Install

  @ets_table :hex_registry
  @version   4
  @wait_time 10_000

  def full_build do
    locked_build(&do_full_rebuild/0)
  end

  defp locked_build(fun) do
    handle = HexWeb.Repo.insert!(HexWeb.Registry.build)

    try do
      HexWeb.Repo.transaction(fn ->
        SQL.query(HexWeb.Repo, "LOCK registries NOWAIT", [])
        run_or_skip(handle, fun)
      end)
    rescue
      error in [Postgrex.Error] ->
        stacktrace = System.stacktrace
        if error.postgres.code == :lock_not_available do
          :timer.sleep(@wait_time)
          run_or_skip(handle, fun)
        else
          reraise error, stacktrace
        end
    end
  end

  defp run_or_skip(handle, fun) do
    unless skip?(handle) do
      HexWeb.Registry.set_working(handle)
      |> HexWeb.Repo.update_all([])

      fun.()

      HexWeb.Registry.set_done(handle)
      |> HexWeb.Repo.update_all([])
    end
  end

  defp skip?(handle) do
    # Has someone already pushed data newer than we were planning push?
    latest_started = HexWeb.Registry.latest_started
                     |> HexWeb.Repo.one

    if latest_started && time_diff(latest_started, handle.inserted_at) > 0 do
      HexWeb.Registry.set_done(handle)
      |> HexWeb.Repo.update_all([])
      true
    else
      false
    end
  end

  defp do_full_rebuild do
    log(:FULL, fn ->
      installs       = installs()
      requirements   = requirements()
      releases       = releases()
      packages       = packages()
      package_tuples = package_tuples(packages, releases)
      release_tuples = release_tuples(packages, releases, requirements)

      ets = build_ets(package_tuples, release_tuples, installs)
      new = build_new(package_tuples, release_tuples)
      # TODO: Delete old files after upload
      upload_files(ets, new)

      # TODO: purge
      # HexWeb.CDN.purge_key(:fastly_hexrepo, "registry")
    end)
  end

  defp log(type, fun) do
    try do
      {time, _} = :timer.tc(fun)

      Logger.warn "REGISTRY_BUILDER_COMPLETED #{type} (#{div time, 1000}ms)"
    catch
      kind, error ->
        stacktrace = System.stacktrace
        Logger.error "REGISTRY_BUILDER_FAILED #{type}"
        HexWeb.Utils.log_error(kind, error, stacktrace)
    end
  end

  defp build_ets(packages, releases, installs) do
    file = Path.join("tmp", "registry-#{:erlang.unique_integer([:positive])}.ets")

    tid = :ets.new(@ets_table, [:public])
    :ets.insert(tid, {:"$$version$$", @version})
    :ets.insert(tid, {:"$$installs2$$", installs})
    :ets.insert(tid, packages)
    :ets.insert(tid, releases)
    :ok = :ets.tab2file(tid, String.to_char_list(file))
    :ets.delete(tid)

    contents = File.read!(file) |> :zlib.gzip
    {contents, try_sign(contents)}
  end

  defp try_sign(contents) do
    if key = Application.get_env(:hex_web, :signing_key) do
      HexWeb.Utils.sign(contents, key)
    end
  end

  defp build_new(packages, releases) do
    {build_names(packages),
     build_versions(packages),
     build_packages(packages, releases)}
  end

  def build_names(packages) do
    packages = Enum.map(packages, fn {name, _versions} -> %{name: name} end)
    %{packages: packages}
    |> :hex_pb_names.encode_msg(:Names)
    |> :zlib.gzip
  end

  def build_versions(packages) do
    packages = Enum.map(packages, fn {name, [versions]} -> %{name: name, versions: versions} end)
    %{packages: packages}
    |> :hex_pb_versions.encode_msg(:Versions)
    |> :zlib.gzip
  end

  def build_packages(packages, releases) do
    release_map = Map.new(releases)

    Enum.map(packages, fn {name, [versions]} ->
      releases =
        Enum.map(versions, fn version ->
          [deps, checksum, _tools] = release_map[{name, version}]
          deps =
            Enum.map(deps, fn [dep, req, opt, app] ->
              map = %{package: dep, requirement: req}
              map = if opt, do: Map.put(map, :optional, true), else: map
              map = if app != dep, do: Map.put(map, :app, app), else: map
              map
            end)

          checksum = checksum |> Base.decode16!
          %{version: version, checksum: checksum, dependencies: deps}
        end)

      contents =
        %{releases: releases}
        |> :hex_pb_package.encode_msg(:Package)
        |> :zlib.gzip

      {name, contents}
    end)
  end

  defp upload_files({ets, ets_sign}, {names, versions, packages}) do
    meta = [{"surrogate-key", "registry registry-all"}]
    ets_meta = if ets_sign, do: [{"signature", ets_sign}|meta], else: meta
    opts = [acl: :public_read, cache_control: "public, max-age=600", meta: meta]
    ets_opts = Keyword.put(opts, :meta, ets_meta)

    ets_object = {"registry.ets.gz", ets, ets_opts}
    ets_sign_object = {"registry.ets.gz.signed", ets_sign, opts}
    names_object = {"names", names, ets_opts}
    versions_object = {"versions", versions, ets_opts}

    package_objects = Enum.map(packages, fn {name, contents} ->
      opts = Keyword.put(opts, :meta, [{"surrogate-key", "registry registry-package-#{name}"}])
      {"packages/#{name}", contents, opts}
    end)

    objects = [
      ets_object,
      ets_sign_object,
      names_object,
      versions_object |
      package_objects]
    |> filter_objects

    HexWeb.Store.put_many(nil, :s3_bucket, objects, [])
  end

  defp filter_objects(objects) do
    Enum.reject(objects, fn {_name, obj, _opts} -> is_nil(obj) end)
  end

  defp package_tuples(packages, releases) do
    Enum.reduce(releases, %{}, fn {_, vsn, pkg_id, _, _}, map ->
      case Map.fetch(packages, pkg_id) do
        {:ok, package} -> Map.update(map, package, [vsn], &[vsn|&1])
        :error -> map
      end
    end)
    |> sort_package_tuples
  end

  defp sort_package_tuples(tuples) do
    Enum.map(tuples, fn {name, versions} ->
      versions =
        Enum.sort(versions, &(Version.compare(&1, &2) == :lt))
        |> Enum.map(&to_string/1)

      {name, [versions]}
    end)
    |> Enum.sort
  end

  defp release_tuples(packages, releases, requirements) do
    Enum.flat_map(releases, fn {id, version, pkg_id, checksum, tools} ->
      case Map.fetch(packages, pkg_id) do
        {:ok, package} ->
          deps = deps_list(requirements[id] || [], packages)
          [{{package, to_string(version)}, [deps, checksum, tools]}]
        :error ->
          []
      end
    end)
  end

  defp deps_list(requirements, packages) do
    Enum.flat_map(requirements, fn {dep_id, app, req, opt} ->
      case Map.fetch(packages, dep_id) do
        {:ok, dep} -> [[dep, req, opt, app]]
        :error -> []
      end
    end)
    |> Enum.sort
  end

  defp packages do
    from(p in Package, select: {p.id, p.name})
    |> HexWeb.Repo.all
    |> Enum.into(%{})
  end

  defp releases do
    from(r in Release, select: {r.id, r.version, r.package_id, r.checksum, fragment("?->'build_tools'", r.meta)})
    |> HexWeb.Repo.all
  end

  defp requirements do
    reqs =
      from(r in Requirement,
           select: {r.release_id, r.dependency_id, r.app, r.requirement, r.optional})
      |> HexWeb.Repo.all

    Enum.reduce(reqs, %{}, fn {rel_id, dep_id, app, req, opt}, map ->
      tuple = {dep_id, app, req, opt}
      Map.update(map, rel_id, [tuple], &[tuple|&1])
    end)
  end

  defp installs do
    Install.all
    |> HexWeb.Repo.all
    |> Enum.map(&{&1.hex, &1.elixirs})
  end

  defp time_diff(time1, time2) do
    time1 = Ecto.DateTime.to_erl(time1) |> :calendar.datetime_to_gregorian_seconds
    time2 = Ecto.DateTime.to_erl(time2) |> :calendar.datetime_to_gregorian_seconds
    time1 - time2
  end
end
