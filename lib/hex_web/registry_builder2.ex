defmodule HexWeb.RegistryBuilder2 do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

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

  def rebuild do
    tmp      = Application.get_env(:hex_web, :tmp_dir)
    reg_file = Path.join(tmp, "registry.ets")
    handle   = HexWeb.Registry.build
               |> HexWeb.Repo.insert!

    rebuild(handle, reg_file)
  end

  defp rebuild(handle, reg_file) do
    try do
      HexWeb.Repo.transaction(fn ->
        SQL.query(HexWeb.Repo, "LOCK registries NOWAIT", [])
        unless skip?(handle) do
          build(handle, reg_file)
        end
      end)
    rescue
      error in [Postgrex.Error] ->
        stacktrace = System.stacktrace
        if error.postgres.code == :lock_not_available do
          :timer.sleep(@wait_time)
          unless skip?(handle) do
            rebuild(handle, reg_file)
          end
        else
          reraise error, stacktrace
        end
    end
  end

  defp build(handle, file) do
    try do
      {time, memory} = :timer.tc(fn ->
        build_ets(handle, file)
      end)

      Logger.warn "REGISTRY_BUILDER_COMPLETED (#{div time, 1000}ms, #{div memory, 1024}kb)"
    catch
      kind, error ->
        stacktrace = System.stacktrace
        Logger.error "REGISTRY_BUILDER_FAILED"
        HexWeb.Utils.log_error(kind, error, stacktrace)
    end
  end

  defp build_ets(handle, file) do
    HexWeb.Registry.set_working(handle)
    |> HexWeb.Repo.update_all([])

    installs     = installs()
    requirements = requirements()
    releases     = releases()
    packages     = packages()

    package_tuples = package_tuples(packages, releases)
    release_tuples = release_tuples(packages, releases, requirements)

    {:memory, memory} = :erlang.process_info(self, :memory)

    File.rm(file)
    build_ets(file, package_tuples, release_tuples, installs)
    IO.puts "ETS: #{div File.stat!(file).size, 1024}kb"
    # upload_registry(file)

    build_names(package_tuples)
    build_versions(package_tuples)
    build_packages(package_tuples, release_tuples)
    build_releases(package_tuples, release_tuples)

    HexWeb.Registry.set_done(handle)
    |> HexWeb.Repo.update_all([])

    memory
  end

  defp build_ets(file, packages, releases, installs) do
    tid = :ets.new(@ets_table, [:public])
    :ets.insert(tid, {:"$$version$$", @version})
    :ets.insert(tid, {:"$$installs2$$", installs})
    :ets.insert(tid, packages)
    :ets.insert(tid, releases)
    :ok = :ets.tab2file(tid, String.to_char_list(file))
    :ets.delete(tid)
  end

  # TODO
  # gzip tarball instead?
  # defp build_full(packages, releases) do
  # end

  def build_names(packages) do
    contents =
      Enum.reduce(packages, "", fn {name, _}, acc ->
        [acc, name, "\n"]
      end)
    write_file("names", contents)
  end

  def build_versions(packages) do
    contents =
      Enum.reduce(packages, "", fn {name, [versions]}, acc ->
        contents =
          Enum.reduce(versions, [acc, name], fn version, acc ->
            [acc, " ", version]
          end)

        [contents, "\n"]
      end)

    write_file("versions", contents)
  end

  def build_packages(packages, releases) do
    releases = Map.new(releases)

    Enum.each(packages, fn {name, [versions]} ->
      contents =
        Enum.reduce(versions, "", fn version, acc ->
          [deps, checksum, _tools] = releases[{name, version}]
          acc = [acc, version, " ", String.downcase(checksum), "\n"]

          Enum.reduce(deps, acc, fn [dep, req, opt, app], acc ->
            [acc, "  ", dep, " \"", req(req), "\" ", app(dep, app), " ", flags(opt), "\n"]
          end)
        end)

      write_file("packages/#{name}", contents)
    end)
    tar("packages")
  end

  def build_releases(packages, releases) do
    releases = Map.new(releases)

    Enum.each(packages, fn {name, [versions]} ->
      Enum.each(versions, fn version ->
        [deps, checksum, _tools] = releases[{name, version}]
        acc = [String.downcase(checksum), "\n"]

        contents =
          Enum.reduce(deps, acc, fn [dep, req, opt, app], acc ->
            [acc, "  ", dep, " \"", req(req), "\" ", app(dep, app), " ", flags(opt), "\n"]
          end)

        write_file("releases/#{name}/#{version}", contents)
      end)
    end)
    tar("releases")
  end

  defp app(dep, dep), do: "-"
  defp app(_dep, app), do: app

  defp req(nil), do: ">= 0.0.0"
  defp req(req), do: req

  defp flags(true), do: "o"
  defp flags(false), do: "-"

  defp tar(dir) do
    File.cd!(Path.join("registry", dir), fn ->
      filename = '../#{dir}.tar'
      files = File.ls! |> Enum.map(&String.to_charlist/1)
      :ok = :erl_tar.create(filename, files)
      :ok = :erl_tar.create(filename ++ '.gz', files, [:compressed])
    end)
  end

  defp write_file(path, contents) do
    Path.join("registry", path) |> Path.dirname |> File.mkdir_p!
    Path.join(["registry", "gzip", path]) |> Path.dirname |> File.mkdir_p!

    File.write!(Path.join("registry", path), contents)
    File.write!(Path.join(["registry", "gzip", path]), :zlib.gzip(contents))
  end

  defp build_plain(file, packages, releases, installs) do
    contents = [
      build_header(),
      build_packages(packages),
      build_releases(releases),
      build_installs(installs)
    ]
    File.write!(file, contents)
  end

  defp build_header do
    ["HEX ", Integer.to_string(@version), ".0\n"]
  end

  defp upload_registry(file) do
    output = File.read!(file) |> :zlib.gzip

    signature =
      if key = Application.get_env(:hex_web, :signing_key) do
        HexWeb.Utils.sign(output, key)
      end

    meta = [{"surrogate-key", "registry"}]
    sig_opts = [acl: :public_read, cache_control: "public, max-age=600", meta: meta]
    meta = if signature, do: [{"signature", signature}|meta], else: meta
    reg_opts = [acl: :public_read, cache_control: "public, max-age=600", meta: meta]

    objects = [{"registry.ets.gz", output, reg_opts}]
    objects = if signature,
                do: [{"registry.ets.gz.signed", signature, sig_opts}|objects],
              else: objects
    HexWeb.Store.put(nil, :s3_bucket, objects, [])
    HexWeb.CDN.purge_key(:fastly_hexrepo, "registry")
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
