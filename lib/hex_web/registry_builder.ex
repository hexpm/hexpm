defmodule HexWeb.RegistryBuilder do
  @doc """
  Builds the dets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  use GenServer.Behaviour
  import Ecto.Query, only: [from: 2]
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.Requirement

  @dets_table :hex_registry
  @version    1

  defrecordp :state, [building: false, pending: false, waiters: [], tmp_path: nil]

  def start_link() do
    :gen_server.start_link({ :local, __MODULE__ }, __MODULE__, [], [])
  end

  def stop do
    :gen_server.call(__MODULE__, :stop)
  end

  def rebuild do
    :gen_server.cast(__MODULE__, :rebuild)
  end

  def file_path do
    :gen_server.call(__MODULE__, :file_path)
  end

  def init(_) do
    # Store expanded tmp path so we dont brake if cwd changes
    # This is used when integration testing client
    { :ok, state(tmp_path: Path.expand("tmp")) }
  end

  def handle_cast(:rebuild, state(building: false, tmp_path: tmp) = s) do
    build(tmp)
    { :noreply, state(s, building: true) }
  end

  def handle_cast(:rebuild, state(building: true) = s) do
    { :noreply, state(s, pending: true) }
  end

  def handle_call(:stop, _from, s) do
    { :stop, :normal, :ok, s }
  end

  def handle_call(:file_path, from, state(building: true, waiters: waiters) = s) do
    { :noreply, state(s, waiters: [from|waiters]) }
  end

  def handle_call(:file_path, _from, state(building: false, tmp_path: tmp_path) = s) do
    latest = file_path(s)

    ["", version]  = Path.basename(latest) |> String.split("registry-")
    { version, _ } = Integer.parse(version)

    if registry = HexWeb.Registry.get(version) do
      temp_file = Path.join(tmp_path, "registry-dbtemp.dets")
      reg_file  = Path.join(tmp_path, "registry-#{version}.dets")

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
    path = file_path(s)
    Enum.each(waiters, &:gen_server.reply(&1, path))
    state(s, waiters: [])
  end

  defp file_path(state(tmp_path: tmp_path)) do
    Path.join(tmp_path, "registry-*.dets")
    |> Path.wildcard
    |> List.last
  end

  defp build(tmp_path) do
    pid = self()
    spawn_link(fn ->
      builder(pid, tmp_path)
    end)
  end

  defp builder(pid, tmp_path) do
    packages     = packages()
    releases     = releases()
    requirements = requirements()

    tuples =
      Enum.map(releases, fn { id, version, git_url, git_ref, pkg_id } ->
        package = packages[pkg_id]
        deps =
          Enum.map(requirements[id] || [], fn { dep_id, req } ->
            dep_name = packages[dep_id]
            { dep_name, req }
          end)
        { package, version, deps, git_url, git_ref }
      end)

    temp_file = Path.join(tmp_path, "registry-temp.dets")
    File.rm(temp_file)

    dets_opts = [
      file: temp_file,
      ram_file: true,
      auto_save: :infinity,
      min_no_slots: Dict.size(packages) + 1,
      type: :duplicate_bag ]

    { :ok, @dets_table } = :dets.open_file(@dets_table, dets_opts)
    :ok = :dets.insert(@dets_table, { :"$$version$$", @version })
    :ok = :dets.insert(@dets_table, tuples)
    :ok = :dets.close(@dets_table)

    version = Enum.reduce(releases, 1, &max(elem(&1, 0), &2))
    reg_file = Path.join(tmp_path, "registry-#{version}.dets")
    :ok = :file.rename(temp_file, reg_file)
    File.rm(temp_file)

    HexWeb.Registry.create(version, File.read!(reg_file))

    send pid, :finished_building
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
