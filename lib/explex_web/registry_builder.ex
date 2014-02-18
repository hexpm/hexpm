defmodule ExplexWeb.RegistryBuilder do
  @doc """
  Builds the dets registry file. Only one build process should run at a given
  time, but if a rebuild request comes in during building we need to rebuild
  immediately after again.
  """

  use GenServer.Behaviour
  import Ecto.Query, only: [from: 2]
  alias ExplexWeb.Package
  alias ExplexWeb.Release
  alias ExplexWeb.Requirement

  @reg_file   "registry.dets"
  @temp_file  "registry-temp.dets"
  @dets_table :explex_registry
  @version    1

  defrecordp :state, [building: false, pending: false, waiter: nil, tmp_path: nil]

  def start_link(opts \\ []) do
    :gen_server.start_link({ :local, __MODULE__ }, __MODULE__, opts, [])
  end

  def stop do
    :gen_server.call(__MODULE__, :stop)
  end

  def wait_for_build do
    :gen_server.call(__MODULE__, :wait_for_build)
  end

  def rebuild do
    :gen_server.cast(__MODULE__, :rebuild)
  end

  def filename do
    :gen_server.call(__MODULE__, :filename)
  end

  def init(opts) do
    if opts[:build_on_start], do: rebuild()
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

  def handle_call(:wait_for_build, _from, state(building: false) = s) do
    { :reply, :ok, s }
  end

  def handle_call(:wait_for_build, from, state(building: true) = s) do
    { :noreply, state(s, waiter: from) }
  end

  def handle_call(:filename, _from, state(tmp_path: tmp_path) = s) do
    path = Path.join(tmp_path, @reg_file)
    { :reply, path, s }
  end

  def handle_info(:finished_building, state(pending: pending, waiter: waiter) = s) do
    if pending, do: rebuild()
    if waiter, do: :gen_server.reply(waiter, :ok)
    { :noreply, state(s, building: false, pending: false, waiter: nil) }
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

    temp_file = Path.join(tmp_path, @temp_file)
    reg_file = Path.join(tmp_path, @reg_file)
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
    :ok = :file.rename(temp_file, reg_file)

    send pid, :finished_building
  end

  defp packages do
    from(p in Package, select: { p.id, p.name })
    |> ExplexWeb.Repo.all
    |> HashDict.new
  end

  defp releases do
    from(r in Release,
         select: { r.id, r.version, r.git_url, r.git_ref, r.package_id })
    |> ExplexWeb.Repo.all
  end

  defp requirements do
    reqs =
      from(r in Requirement,
           select: { r.release_id, r.dependency_id, r.requirement })
      |> ExplexWeb.Repo.all

    Enum.reduce(reqs, HashDict.new, fn { rel_id, dep_id, req }, dict ->
      tuple = { dep_id, req }
      Dict.update(dict, rel_id, [tuple], &[tuple|&1])
    end)
  end
end
