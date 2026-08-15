defmodule Hexpm.Hexdocs.Debouncer do
  use GenServer

  @timeout 60_000

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, [], Keyword.take(opts, [:name]))

  def debounce(server, key, timeout, fun) do
    case GenServer.call(server, {:debounce, key, timeout}, @timeout) do
      :go -> {:ok, fun.()}
      :debounced -> :debounced
    end
  end

  @impl true
  def init([]), do: {:ok, %{}}

  @impl true
  def handle_call({:debounce, key, timeout}, from, state) do
    case Map.fetch(state, key) do
      {:ok, froms} ->
        {:noreply, Map.put(state, key, [from | froms])}

      :error ->
        Process.send_after(self(), {:deadline, key, timeout}, timeout)
        {:reply, :go, Map.put(state, key, [])}
    end
  end

  @impl true
  def handle_info({:deadline, key, timeout}, state) do
    case Map.fetch!(state, key) do
      [] ->
        {:noreply, Map.delete(state, key)}

      froms ->
        {debounced, go} = Enum.split(froms, -1)
        Enum.each(debounced, &GenServer.reply(&1, :debounced))
        Enum.each(go, &GenServer.reply(&1, :go))
        Process.send_after(self(), {:deadline, key, timeout}, timeout)
        {:noreply, Map.put(state, key, [])}
    end
  end
end
