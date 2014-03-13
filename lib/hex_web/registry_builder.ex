defmodule HexWeb.RegistryBuilder do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  use GenServer.Behaviour
  import Ecto.Query, only: [from: 2]
  require HexWeb.Repo
  alias Ecto.Adapters.Postgres
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Requirement

  @ets_table :hex_registry
  @version    1

  defrecordp :state, [building: false, pending: false, waiters: []]

  def start_link() do
    :gen_server.start_link({ :local, __MODULE__ }, __MODULE__, [], [])
  end

  def stop do
    :gen_server.call(__MODULE__, :stop)
  end

  def rebuild do
    :gen_server.cast(__MODULE__, :rebuild)
  end

  def wait_for_build do
    :gen_server.call(__MODULE__, :wait_for_build)
  end

  def init(_) do
    { :ok, state() }
  end

  def handle_cast(:rebuild, state(building: false) = s) do
    build()
    { :noreply, state(s, building: true) }
  end

  def handle_cast(:rebuild, state(building: true) = s) do
    { :noreply, state(s, pending: true) }
  end

  def handle_call(:stop, _from, s) do
    { :stop, :normal, :ok, s }
  end

  def handle_call(:wait_for_build, from, state(building: true, waiters: waiters) = s) do
    { :noreply, state(s, waiters: [from|waiters]) }
  end

  def handle_call(:wait_for_build, _from, state(building: false) = s) do
    { :reply, :ok, s }
  end

  def handle_info(:finished_building, state(pending: pending) = s) do
    if pending, do: rebuild()
    s = reply_to_waiters(s)
    { :noreply, state(s, building: false, pending: false) }
  end

  defp reply_to_waiters(state(waiters: waiters) = s) do
    Enum.each(waiters, &:gen_server.reply(&1, :ok))
    state(s, waiters: [])
  end

  defp build do
    pid = self()
    spawn_link(fn ->
      builder(pid)
    end)
  end

  defp builder(pid) do
    reg_file = Path.expand("tmp/registry.ets")
    { :ok, handle } = HexWeb.Registry.create()
    build_ets(handle, reg_file)

    send pid, :finished_building
  end

  def build_ets(handle, file) do
    try do
      HexWeb.Repo.transaction(fn ->
        Postgres.query(HexWeb.Repo, "LOCK registries NOWAIT")

        unless skip?(handle) do
          HexWeb.Registry.set_working(handle)

          requirements = requirements()
          releases     = releases()
          packages     = packages()

          package_tuples =
            Enum.reduce(releases, HashDict.new, fn { _, vsn, _, _, pkg_id }, dict ->
              Dict.update(dict, packages[pkg_id], [vsn], &[vsn|&1])
            end)

          package_tuples =
            Enum.map(package_tuples, fn { name, vsns } ->
              { name, Enum.sort(vsns, &(Version.compare(&1, &2) == :lt)) }
            end)

          release_tuples =
            Enum.map(releases, fn { id, version, git_url, git_ref, pkg_id } ->
              package = packages[pkg_id]
              deps =
                Enum.map(requirements[id] || [], fn { dep_id, req } ->
                  dep_name = packages[dep_id]
                  { dep_name, req }
                end)
              { { package, version }, deps, git_url, git_ref }
            end)

          File.rm(file)

          tid = :ets.new(@ets_table, [:public])
          :ets.insert(tid, { :"$$version$$", @version })
          :ets.insert(tid, release_tuples ++ package_tuples)
          :ok = :ets.tab2file(tid, String.to_char_list!(file))
          :ets.delete(tid)

          HexWeb.Config.store.put_registry(File.read!(file))
          HexWeb.Registry.set_done(handle)
        end
      end)
    rescue
      error in [Postgrex.Error] ->
        if error.code == "55P03" do
          :timer.sleep(10_000)
          unless skip?(handle) do
            build_ets(handle, file)
          end
        end
    end
  end

  defp skip?(handle) do
    # Has someone already pushed data newer than we were planning push?
    latest_started = HexWeb.Registry.latest_started

    if latest_started && time_diff(latest_started, handle.created) > 0 do
      HexWeb.Registry.set_done(handle)
      true
    else
      false
    end
  end

  defp packages do
    from(p in Package, select: { p.id, p.name })
    |> HexWeb.Repo.all
    |> HashDict.new
  end

  defp releases do
    from(r in Release,
         select: { r.id, r.version, r.git_url, r.git_ref, r.package_id })
    |> HexWeb.Repo.all
  end

  defp requirements do
    reqs =
      from(r in Requirement,
           select: { r.release_id, r.dependency_id, r.requirement })
      |> HexWeb.Repo.all

    Enum.reduce(reqs, HashDict.new, fn { rel_id, dep_id, req }, dict ->
      tuple = { dep_id, req }
      Dict.update(dict, rel_id, [tuple], &[tuple|&1])
    end)
  end

  defp time_diff(time1, time2) do
    time1 = Ecto.DateTime.to_erl(time1) |> :calendar.datetime_to_gregorian_seconds
    time2 = Ecto.DateTime.to_erl(time2) |> :calendar.datetime_to_gregorian_seconds
    time1 - time2
  end
end
