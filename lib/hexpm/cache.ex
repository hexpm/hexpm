defmodule Hexpm.Cache do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def fetch(table \\ __MODULE__, key, fun) do
    case :ets.whereis(table) do
      :undefined ->
        fun.()

      _ ->
        case :ets.lookup(table, key) do
          [{^key, value, _fun}] ->
            value

          [] ->
            value = fun.()
            :ets.insert(table, {key, value, fun})
            value
        end
    end
  end

  def refresh(server \\ __MODULE__) do
    GenServer.call(server, :refresh)
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled, true) do
      table = opts[:name] || __MODULE__
      :ets.new(table, [:named_table, :public, :set, read_concurrency: true])
      state = %{table: table, interval: opts[:interval]}
      schedule(state)
      {:ok, state}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:update, state) do
    populate(state)
    schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    populate(state)
    {:reply, :ok, state}
  end

  defp populate(%{table: table}) do
    for {key, _value, fun} <- :ets.tab2list(table) do
      :ets.insert(table, {key, fun.(), fun})
    end
  end

  defp schedule(%{interval: interval}) do
    Process.send_after(self(), :update, interval)
  end
end
