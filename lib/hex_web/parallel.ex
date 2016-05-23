defmodule HexWeb.Parallel do
  use GenServer
  require Logger

  @timeout 60 * 1000

  def run(fun, args, opts \\ [])

  def run(_fun, [], _opts), do: []
  def run(fun, args, opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, new_state(opts))
    try do
      timeout = Keyword.get(opts, :timeout, @timeout)
      GenServer.call(pid, {:run, fun, args}, timeout)
    after
      GenServer.stop(pid)
    end
  end

  def run!(fun, args, opts \\ [])

  def run!(fun, args, opts) do
    results = run(fun, args, opts)
    if Enum.any?(results, &match?({:error, _}, &1)) do
      raise "Parallel tasks failed"
    end
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:run, fun, args}, from, state) do
    state = %{state | fun: fun, args: args, from: from, num_jobs: length(args), num_finished: 0}
    state = run_tasks(state)
    {:noreply, state}
  end

  def handle_info({ref, message}, state) when is_reference(ref) do
    state =
      state
      |> maybe_next_task(Map.has_key?(state.running, ref), ref, {:ok, message})
      |> maybe_reply

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, _, _proc, reason}, state) do
    case Map.fetch(state.running, ref) do
      {:ok, arg} ->
        Logger.error(["Parallel task failed with reason: `", inspect(reason), "` and args: `", inspect(arg), "`"])
        {:noreply, state
                   |> maybe_next_task(true, ref, {:error, arg})
                   |> maybe_reply}
      :error ->
        {:noreply, state}
    end
  end

  defp maybe_next_task(state, true, ref, result) do
    state = %{state | running: Map.delete(state.running, ref),
                      finished: [result|state.finished],
                      num_finished: state.num_finished + 1}

    run_task(state)
  end
  defp maybe_next_task(state, false, _ref, _message), do: state

  defp maybe_reply(%{num_finished: finished, num_jobs: jobs} = state)
      when finished >= jobs do
    GenServer.reply(state.from, state.finished)
    %{state | finished: [], fun: nil, args: nil, from: nil, num_jobs: nil,
              num_finished: nil}
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
        task = Task.async(fn -> state.fun.(arg) end)
        %{state | running: Map.put(state.running, task.ref, arg), args: args}
      [] ->
        state
    end
  end

  defp new_state(opts) do
    %{max_jobs: parallel(opts[:parallel]),
      running: Map.new,
      finished: [],
      waiting: [],
      num_jobs: nil,
      num_finished: nil,
      fun: nil,
      args: nil,
      from: nil}
  end

  if Mix.env == :test do
    defp parallel(_arg), do: 1
  else
    defp parallel(arg), do: arg || 50
  end
end
