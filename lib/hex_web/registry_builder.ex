defmodule HexWeb.RegistryBuilder do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  require Logger
  alias Ecto.Adapters.Postgres
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Requirement
  alias HexWeb.Install

  @ets_table :hex_registry
  @version   3
  @wait_time 10_000

  def rebuild do
    tmp = Application.get_env(:hex_web, :tmp)
    reg_file = Path.join(tmp, "registry.ets")
    {:ok, handle} = HexWeb.Registry.create()
    rebuild(handle, reg_file)
  end

  defp rebuild(handle, reg_file) do
    try do
      HexWeb.Repo.transaction(fn ->
        Postgres.query(HexWeb.Repo, "LOCK registries NOWAIT", [])
        unless skip?(handle) do
          build(handle, reg_file)
        end
      end)
    rescue
      error in [Postgrex.Error] ->
        stacktrace = System.stacktrace
        if error.code == "55P03" do
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

      Logger.info "REGISTRY_BUILDER_COMPLETED (#{div time, 1000}ms, #{div memory, 1024}kb)"
    catch
      kind, error ->
        stacktrace = System.stacktrace
        Logger.error "REGISTRY_BUILDER_FAILED"
        HexWeb.Util.log_error(kind, error, stacktrace)
    end
  end

  def build_ets(handle, file) do
    HexWeb.Registry.set_working(handle)

    {installs1, installs2} = installs()
    requirements = requirements()
    releases     = releases()
    packages     = packages()

    package_tuples =
      Enum.reduce(releases, HashDict.new, fn {_, vsn, pkg_id, _}, dict ->
        Dict.update(dict, packages[pkg_id], [vsn], &[vsn|&1])
      end)

    package_tuples =
      Enum.map(package_tuples, fn {name, vsns} ->
        {name, [Enum.sort(vsns, &(Version.compare(&1, &2) == :lt))]}
      end)

    release_tuples =
      Enum.map(releases, fn {id, version, pkg_id, checksum} ->
        package = packages[pkg_id]
        deps =
          Enum.map(requirements[id] || [], fn {dep_id, app, req, opt} ->
            dep_name = packages[dep_id]
            [dep_name, req, opt, app]
          end)
        {{package, version}, [deps, checksum]}
      end)

    {:memory, memory} = :erlang.process_info(self, :memory)

    File.rm(file)

    tid = :ets.new(@ets_table, [:public])
    :ets.insert(tid, {:"$$version$$", @version})
    # Removing :"$$installs$$" should bump version to 4
    # :"$$installs2$$" was added with Hex v0.5.0 (Elixir v1.0.0) (2014-09-19)
    :ets.insert(tid, {:"$$installs$$", installs1})
    :ets.insert(tid, {:"$$installs2$$", installs2})
    :ets.insert(tid, release_tuples ++ package_tuples)
    :ok = :ets.tab2file(tid, String.to_char_list(file))
    :ets.delete(tid)

    Application.get_env(:hex_web, :store).put_registry(File.read!(file))
    HexWeb.Registry.set_done(handle)

    memory
  end

  defp skip?(handle) do
    # Has someone already pushed data newer than we were planning push?
    latest_started = HexWeb.Registry.latest_started

    if latest_started && time_diff(latest_started, handle.created_at) > 0 do
      HexWeb.Registry.set_done(handle)
      true
    else
      false
    end
  end

  defp packages do
    from(p in Package, select: {p.id, p.name})
    |> HexWeb.Repo.all
    |> Enum.into(HashDict.new)
  end

  defp releases do
    from(r in Release, select: {r.id, r.version, r.package_id, r.checksum})
    |> HexWeb.Repo.all
  end

  defp requirements do
    reqs =
      from(r in Requirement,
           select: {r.release_id, r.dependency_id, r.app, r.requirement, r.optional})
      |> HexWeb.Repo.all

    Enum.reduce(reqs, HashDict.new, fn {rel_id, dep_id, app, req, opt}, dict ->
      tuple = {dep_id, app, req, opt}
      Dict.update(dict, rel_id, [tuple], &[tuple|&1])
    end)
  end

  defp installs do
    installs2 =
      Enum.map(Install.all, fn %Install{hex: hex, elixirs: elixirs} ->
        {hex, elixirs}
      end)

    installs1 = Enum.map(installs2, fn {hex, elixirs} -> {hex, List.first(elixirs)} end)

    {installs1, installs2}
  end

  defp time_diff(time1, time2) do
    time1 = Ecto.DateTime.to_erl(time1) |> :calendar.datetime_to_gregorian_seconds
    time2 = Ecto.DateTime.to_erl(time2) |> :calendar.datetime_to_gregorian_seconds
    time1 - time2
  end
end
