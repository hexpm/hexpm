defmodule Hexpm.Throttle do
  use GenServer
  require Logger

  @timeout 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, new_state(opts), opts)
  end

  def wait(pid, increment, timeout \\ @timeout) when increment >= 1 do
    try do
      GenServer.call(pid, {:run, increment}, timeout)
    catch
      :exit, :timeout ->
        GenServer.cast(pid, {:cancel, self()})
        exit(:timeout)
    end
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:run, increment}, _, %{rate: rate}) when increment > rate do
    raise "increase must not exceed rate: #{inspect(rate)}, got: #{inspect(increment)}"
  end

  def handle_call({:run, increment}, from, state) do
    first_during_unit? = state.running == 0

    state = %{state | waiting: :queue.in({from, increment}, state.waiting)}
    {_, state} = try_run(state)

    if first_during_unit? do
      :erlang.send_after(state.unit, self(), :reset)
    end

    {:noreply, state}
  end

  def handle_call({:cancel, pid}, state) do
    state = %{state | cancel: MapSet.put(state.cancel, pid)}
    {:noreply, state}
  end

  def handle_info(:reset, state) do
    empty? = :queue.is_empty(state.waiting)

    state =
      %{state | running: 0}
      |> filter_canceled()
      |> churn_queue()

    unless empty? do
      :erlang.send_after(state.unit, self(), :reset)
    end

    {:noreply, state}
  end

  defp try_run(state) do
    case :queue.out(state.waiting) do
      {{:value, {from, increment}}, waiting} ->
        if state.running + increment <= state.rate do
          GenServer.reply(from, :yes)
          {true, %{state | running: state.running + increment, waiting: waiting}}
        else
          {false, state}
        end

      {:empty, _} ->
        {false, state}
    end
  end

  defp filter_canceled(state) do
    fun = fn {pid, _} -> not MapSet.member?(state.cancel, pid) end
    waiting = :queue.filter(fun, state.waiting)
    %{state | waiting: waiting, cancel: MapSet.new()}
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
    %{
      rate: opts[:rate],
      unit: opts[:unit],
      waiting: :queue.new(),
      cancel: MapSet.new(),
      running: 0
    }
  end
end
