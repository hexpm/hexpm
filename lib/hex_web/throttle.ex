defmodule HexWeb.Throttle do
  use GenServer
  require Logger

  @timeout 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, new_state(opts), opts)
  end

  def wait(pid, timeout \\ @timeout) do
    try do
      GenServer.call(pid, :run, timeout)
    catch
      :exit, :timeout ->
        GenServer.cast(pid, {:cancel, self()})
        exit(:timeout)
    end
  end

  def handle_call(:run, from, state) do
    first_during_unit? = state.running == 0

    state = %{state | waiting: :queue.in(from, state.waiting)}
    {_, state} = try_run(state)

    if first_during_unit?,
      do: :erlang.send_after(state.unit, self(), :reset)

    {:noreply, state}
  end

  def handle_call({:cancel, pid}, state) do
    state = %{state | cancel: MapSet.put(state.cancel, pid)}
    {:noreply, state}
  end

  def handle_in(:reset, state) do
    empty? = :queue.is_empty(state.waiting)
    state  = %{state | running: 0}
    state  = filter_canceled(state)
    state  = churn_queue(state)

    unless empty?,
      do: :erlang.send_after(state.unit, self(), :reset)

    {:noreply, state}
  end

  defp try_run(state) do
    if state.running < state.rate do
      case :queue.out(state.waiting) do
        {{:value, from}, waiting} ->
          GenServer.reply(from, :yes)
          {true, %{state | running: state.running+1, waiting: waiting}}
        {:empty, _} ->
          {false, state}
      end
    else
      {false, state}
    end
  end

  defp filter_canceled(state) do
    fun = fn {pid, _} -> not MapSet.member?(state.cancel, pid) end
    waiting = :queue.filter(fun, state)
    %{state | waiting: waiting, cancel: MapSet.new}
  end

  defp churn_queue(state) do
    case try_run(state) do
      {true, state} ->
        churn_queue(state)
      {false, state} ->
        state
    end
  end

  defp new_state(opts) do
    %{rate: opts[:rate],
      unit: opts[:unit],
      waiting: :queue.new,
      cancel: MapSet.new,
      running: 0}
  end
end
