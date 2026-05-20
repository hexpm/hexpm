defmodule Hexpm.Cache do
  @table __MODULE__

  def start(table \\ @table) do
    :ets.new(table, [:named_table, :public, :set, read_concurrency: true])
    :ok
  end

  def fetch(table \\ @table, key, fun, ttl)

  def fetch(table, key, fun, ttl) do
    case :ets.whereis(table) do
      :undefined -> fun.()
      _ -> do_fetch(table, key, fun, ttl)
    end
  end

  def invalidate(table \\ @table, key)

  def invalidate(table, key) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ -> :ets.delete(table, key)
    end

    :ok
  end

  defp do_fetch(table, key, fun, ttl) do
    now = System.monotonic_time(:second)

    case :ets.lookup(table, key) do
      [{^key, value, _fun, inserted_at}] when ttl == :infinity or now - inserted_at < ttl ->
        value

      [{^key, value, _fun, _inserted_at}] ->
        refresh_async(table, key, fun)
        value

      [] ->
        compute_cold(table, key, fun)
    end
  end

  defp refresh_async(table, key, fun) do
    if :ets.insert_new(table, {{:refreshing, key}}) do
      Task.start(fn ->
        try do
          value = fun.()
          :ets.insert(table, {key, value, fun, System.monotonic_time(:second)})
        after
          :ets.delete(table, {:refreshing, key})
        end
      end)
    end

    :ok
  end

  defp compute_cold(table, key, fun) do
    case :ets.lookup(table, {:populating, key}) do
      [{_, leader}] ->
        wait_for(leader, table, key, fun)

      [] ->
        worker =
          spawn(fn ->
            receive do
              :proceed ->
                try do
                  value = fun.()
                  :ets.insert(table, {key, value, fun, System.monotonic_time(:second)})
                after
                  :ets.delete(table, {:populating, key})
                end

              :abort ->
                :ok
            end
          end)

        if :ets.insert_new(table, {{:populating, key}, worker}) do
          send(worker, :proceed)
          wait_for(worker, table, key, fun)
        else
          send(worker, :abort)

          case :ets.lookup(table, {:populating, key}) do
            [{_, leader}] -> wait_for(leader, table, key, fun)
            [] -> fetch(table, key, fun, :infinity)
          end
        end
    end
  end

  defp wait_for(pid, table, key, fun) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} -> fetch(table, key, fun, :infinity)
    end
  end
end
