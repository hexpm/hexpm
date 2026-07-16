defmodule Hexpm.TmpDir do
  use GenServer

  import Bitwise

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def tmp_file(prefix) do
    path = path(prefix)
    File.touch!(path)
    track(path)
    path
  end

  def tmp_dir(prefix) do
    path = path(prefix)
    File.mkdir_p!(path)
    track(path)
    path
  end

  def ensure_readable(path), do: ensure_readable_path(path)

  defp ensure_readable_path(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory, mode: mode}} ->
        if band(mode, 0o500) != 0o500, do: File.chmod!(path, bor(band(mode, 0o7777), 0o500))

        path
        |> File.ls!()
        |> Enum.each(&ensure_readable_path(Path.join(path, &1)))

      {:ok, %{type: :regular, mode: mode}} ->
        if band(mode, 0o400) == 0, do: File.chmod!(path, bor(band(mode, 0o7777), 0o400))

      {:ok, _other} ->
        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file information", path: path
    end
  end

  def cleanup do
    pid = self()
    entries = :ets.lookup(@table, pid)

    Enum.each(entries, fn {_pid, path} ->
      File.rm_rf(path)
    end)

    :ets.delete(@table, pid)
  end

  def await_cleanup(pid) do
    GenServer.call(__MODULE__, {:await_cleanup, pid}, 5000)
  end

  defp path(prefix) do
    random = Base.encode16(:crypto.strong_rand_bytes(4))
    Path.join(base_dir(), prefix <> "-" <> random)
  end

  defp base_dir do
    dir = Application.get_env(:hexpm, :tmp_dir) || System.tmp_dir!()
    File.mkdir_p!(dir)
    dir
  end

  defp track(path) do
    pid = self()
    :ets.insert(@table, {pid, path})
    GenServer.call(__MODULE__, {:monitor, pid})
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:named_table, :duplicate_bag, :public])
    {:ok, %{monitors: MapSet.new(), waiters: %{}}}
  end

  @impl true
  def handle_call({:monitor, pid}, _from, state) do
    if pid in state.monitors do
      {:reply, :ok, state}
    else
      Process.monitor(pid)
      {:reply, :ok, %{state | monitors: MapSet.put(state.monitors, pid)}}
    end
  end

  @impl true
  def handle_call({:await_cleanup, pid}, from, state) do
    if pid in state.monitors do
      waiters = Map.update(state.waiters, pid, [from], &[from | &1])
      {:noreply, %{state | waiters: waiters}}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cleanup_pid(pid)

    for from <- Map.get(state.waiters, pid, []) do
      GenServer.reply(from, :ok)
    end

    {:noreply,
     %{
       state
       | monitors: MapSet.delete(state.monitors, pid),
         waiters: Map.delete(state.waiters, pid)
     }}
  end

  @impl true
  def terminate(_reason, _state) do
    :ets.foldl(
      fn {_pid, path}, :ok ->
        File.rm_rf(path)
        :ok
      end,
      :ok,
      @table
    )
  end

  defp cleanup_pid(pid) do
    entries = :ets.lookup(@table, pid)

    Enum.each(entries, fn {_pid, path} ->
      File.rm_rf(path)
    end)

    :ets.delete(@table, pid)
  end
end
