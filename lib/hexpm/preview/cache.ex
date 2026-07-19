defmodule Hexpm.Preview.Cache do
  use GenServer

  def start_link(opts) do
    if Keyword.get(opts, :enabled, true) do
      name = Keyword.get(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  def fetch(key, fun), do: fetch(__MODULE__, key, fun)

  def fetch(cache, key, fun) do
    now = System.monotonic_time(:millisecond)

    case lookup(cache, key, now) do
      {:ok, value} ->
        value

      :error ->
        value = fun.()

        if value != nil do
          put(cache, key, value, now)
        end

        value
    end
  end

  def invalidate(package, version) do
    delete(__MODULE__, {:manifest, package, version})
    delete(__MODULE__, {:file_tree, package, version})
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :name, __MODULE__)
    :ets.new(table, [:named_table, :public, :set, read_concurrency: true])

    {:ok,
     %{
       table: table,
       max_entries: Keyword.fetch!(opts, :max_entries),
       ttl: Keyword.fetch!(opts, :ttl)
     }}
  end

  @impl true
  def handle_call({:put, key, value, now}, _from, state) do
    expires_at = now + state.ttl
    :ets.insert(state.table, {key, value, expires_at, now})
    trim(state, now)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :ets.delete(state.table, key)
    {:reply, :ok, state}
  end

  defp lookup(table, key, now) do
    case :ets.whereis(table) do
      :undefined ->
        :error

      _tid ->
        case :ets.lookup(table, key) do
          [{^key, value, expires_at, _accessed_at}] when expires_at > now ->
            :ets.update_element(table, key, {4, now})
            {:ok, value}

          [{^key, _value, _expires_at, _accessed_at}] ->
            :ets.delete(table, key)
            :error

          [] ->
            :error
        end
    end
  end

  defp put(table, key, value, now) do
    if Process.whereis(table) do
      GenServer.call(table, {:put, key, value, now})
    end
  end

  defp delete(table, key) do
    if Process.whereis(table) do
      GenServer.call(table, {:delete, key})
    end
  end

  defp trim(state, now) do
    if :ets.info(state.table, :size) > state.max_entries do
      delete_expired(state.table, now)
    end

    if :ets.info(state.table, :size) > state.max_entries do
      {key, _value, _expires_at, _accessed_at} =
        state.table
        |> :ets.tab2list()
        |> Enum.min_by(&elem(&1, 3))

      :ets.delete(state.table, key)
    end
  end

  defp delete_expired(table, now) do
    :ets.select_delete(table, [{{:_, :_, :"$1", :_}, [{:"=<", :"$1", now}], [true]}])
  end
end
