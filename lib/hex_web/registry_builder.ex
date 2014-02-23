defmodule HexWeb.RegistryBuilder do
  @doc """
  Builds the ets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  use GenServer.Behaviour
  import Ecto.Query, only: [from: 2]
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

  def latest_file do
    latest = latest_path()
    version = latest_version(latest)

    cond do
      registry = HexWeb.Registry.get(version) ->
        :gen_server.call(__MODULE__, { :update_from_db, registry })
      nil?(latest) ->
        rebuild()
        wait_for_build()
        latest_path()
      true ->
        latest
    end
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
    { :reply, latest_path(), s }
  end

  def handle_call({ :update_from_db, _ }, from, state(building: true, waiters: waiters) = s) do
    { :noreply, state(s, waiters: [from|waiters]) }
  end

  def handle_call({ :update_from_db, registry }, _from, state(building: false) = s) do
    latest = latest_path

    if latest_version(latest) < registry.version do
      temp_file = Path.expand("tmp/registry-dbtemp.ets")
      reg_file  = Path.expand("tmp/registry-#{registry.version}.ets")

      File.write!(temp_file, registry.data)
      :ok = :file.rename(temp_file, reg_file)
      latest = reg_file
    end

    { :reply, latest, s }
  end

  def handle_info(:finished_building, state(pending: pending) = s) do
    if pending, do: rebuild()
    s = reply_to_waiters(s)
    { :noreply, state(s, building: false, pending: false) }
  end

  defp reply_to_waiters(state(waiters: waiters) = s) do
    Enum.each(waiters, &:gen_server.reply(&1, latest_path()))
    state(s, waiters: [])
  end

  defp latest_path do
    "tmp/registry-*.ets"
    |> Path.wildcard
    |> List.last
  end

  defp latest_version(nil), do: -1

  defp latest_version(latest) do
    destructure [_, version], Path.basename(latest) |> String.split("registry-")
    case Integer.parse(version || "") do
      { version, _ } -> version
      :error         -> -1
    end
  end

  defp build do
    pid = self()
    spawn_link(fn ->
      builder(pid)
    end)
  end

  defp builder(pid) do
    { temp_file, version } = build_ets()

    reg_file = "tmp/registry-#{version}.ets"
    :ok = :file.rename(temp_file, reg_file)
    File.rm(temp_file)

    HexWeb.Registry.create(version, File.read!(reg_file))

    send pid, :finished_building
  end

  def build_ets do
    packages     = packages()
    releases     = releases()
    requirements = requirements()

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

    temp_file = Path.expand("tmp/registry-temp.ets")
    File.rm(temp_file)

    tid = :ets.new(@ets_table, [:public])
    :ets.insert(tid, { :"$$version$$", @version })
    :ets.insert(tid, release_tuples ++ package_tuples)
    :ok = :ets.tab2file(tid, String.to_char_list!(temp_file))
    :ets.delete(tid)

    { temp_file, Enum.reduce(releases, 0, &max(elem(&1, 0), &2)) }
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
end
