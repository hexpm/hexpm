defmodule HexWeb.Parallel.ETS do
  use GenServer
  require Logger

  def each(fun, num_args, args, opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    ets = GenServer.call(pid, :ets)
    fill_ets(ets, num_args, args)

    try do
      GenServer.call(pid, {:each, fun, num_args}, opts[:timeout])
    after
      GenServer.stop(pid)
    else
      :ok ->
        read_ets(ets)
    end
  end

  defp fill_ets(ets, length, args) do
    args = Enum.zip(0..length-1, args)
    :ets.insert(ets, args)
  end

  def read_ets(ets) do
    :ets.tab2list(ets)
    |> Enum.map(&elem(&1, 1))
  end

  def init(opts) do
    tid = :ets.new(__MODULE__, [:public])
    {:ok, new_state(tid, opts)}
  end

  def handle_call(:ets, _from, state) do
    {:reply, state.ets, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:each, fun, num_jobs}, from, state) do
    state = %{state |
      fun: fun,
      from: from,
      num_jobs: num_jobs,
      num_finished: 0
    }
    state = run_tasks(state)
    {:noreply, state}
  end

  def handle_info({ref, :ok}, state) when is_reference(ref) do
    Map.fetch!(state.running, ref)
    state =
      %{state | running: Map.delete(state.running, ref),
                num_finished: state.num_finished + 1}
      |> run_task
      |> maybe_reply
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, _, _proc, reason}, state) do
    case Map.fetch(state.running, ref) do
      {:ok, {id, arg}} ->
        Logger.error(["Parallel task failed with reason: `", inspect(reason), "` and args: `", inspect(arg), "`"])
        :ets.insert(state.ets, {id, {:error, arg}})
        state =
          %{state | running: Map.delete(state.running, ref),
                    num_finished: state.num_finished + 1}
          |> run_task
          |> maybe_reply
        {:noreply, state}
      :error ->
        {:noreply, state}
    end
  end

  defp maybe_reply(%{num_finished: finished, num_jobs: jobs} = state)
  when finished >= jobs do
    GenServer.reply(state.from, :ok)
    state
  end
  defp maybe_reply(state), do: state

  defp run_tasks(state) do
    Enum.reduce(1..state.max_jobs, state, fn _ix, state ->
      run_task(state)
    end)
  end

  defp run_task(state) do
    case :ets.lookup(state.ets, state.counter) do
      [{id, arg}] ->
        task = Task.Supervisor.async_nolink(HexWeb.Tasks, fn ->
          result = state.fun.(arg)
          :ets.insert(state.ets, {id, {:ok, result}})
          :ok
        end)
        %{state | running: Map.put(state.running, task.ref, {id, arg}),
                  counter: state.counter+1}
      [] ->
        state
    end
  end

  defp new_state(ets, opts) do
    %{max_jobs: opts[:parallel],
      running: Map.new,
      counter: 0,
      ets: ets,
      num_jobs: nil,
      num_finished: nil,
      fun: nil,
      from: nil}
  end
end
