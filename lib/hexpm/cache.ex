defmodule Hexpm.Cache do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def fetch(table \\ __MODULE__, key, fun)

  def fetch(table, key, fun) do
    do_fetch(table, key, fun, [])
  end

  def fetch(table, key, fun, opts) do
    do_fetch(table, key, fun, opts)
  end

  defp do_fetch(table, key, fun, opts) do
    case :ets.whereis(table) do
      :undefined ->
        fun.()

      _ ->
        ttl = Keyword.get(opts, :ttl)
        now = System.monotonic_time(:second)

        case :ets.lookup(table, key) do
          [{^key, value, _fun, inserted_at}]
          when ttl == nil or now - inserted_at < ttl ->
            value

          _ ->
            value = fun.()
            :ets.insert(table, {key, value, fun, now})
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
    now = System.monotonic_time(:second)

    for {key, _value, fun, _ts} <- :ets.tab2list(table) do
      :ets.insert(table, {key, fun.(), fun, now})
    end
  end

  defp schedule(%{interval: interval}) do
    Process.send_after(self(), :update, interval)
  end
end
