defmodule HexWeb.Parallel.Process do
  use GenServer
  require Logger

  def reduce(fun, args, acc, reducer, opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, new_state(opts))

    try do
      GenServer.call(pid, {:reduce, fun, args, reducer, acc}, opts[:timeout])
    after
      GenServer.stop(pid)
    end
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:reduce, fun, args, reducer, acc}, from, state) do
    state = %{state |
      fun: fun,
      args: args,
      reducer: reducer,
      acc: acc,
      from: from,
      num_jobs: length(args),
      num_finished: 0
    }
    state = run_tasks(state)
    {:noreply, state}
  end

  def handle_info({ref, message}, state) when is_reference(ref) do
    state =
      %{state | running: Map.delete(state.running, ref),
                num_finished: state.num_finished + 1,
                acc: state.reducer.({:ok, message}, state.acc)}
      |> run_task
      |> maybe_reply

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, _, _proc, reason}, state) do
    case Map.fetch(state.running, ref) do
      {:ok, arg} ->
        Logger.error(["Parallel task failed with reason: `", inspect(reason), "` and args: `", inspect(arg), "`"])
        state =
          %{state | running: Map.delete(state.running, ref),
                    num_finished: state.num_finished + 1,
                    acc: state.reducer.({:error, arg}, state.acc)}
          |> run_task
          |> maybe_reply
          
      :error ->
        {:noreply, state}
    end
  end

  defp maybe_reply(%{num_finished: finished, num_jobs: jobs, acc: acc} = state)
  when finished >= jobs do
    GenServer.reply(state.from, acc)
    state
  end
  defp maybe_reply(state), do: state

  defp run_tasks(state) do
    Enum.reduce(1..state.max_jobs, state, fn _ix, state ->
      run_task(state)
    end)
  end

  defp run_task(state) do
    case state.args do
      [arg|args] ->
        task = Task.Supervisor.async_nolink(HexWeb.Tasks, fn -> state.fun.(arg) end)
        %{state | running: Map.put(state.running, task.ref, arg), args: args}
      [] ->
        state
    end
  end

  defp new_state(opts) do
    %{max_jobs: opts[:parallel],
      running: Map.new,
      num_jobs: nil,
      num_finished: nil,
      fun: nil,
      args: nil,
      reducer: nil,
      acc: nil,
      from: nil}
  end
end
