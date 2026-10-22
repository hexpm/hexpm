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

  @doc """
  Computes `key` again now, unless its value is younger than `min_age`
  seconds. An error result is returned without replacing the cached value.
  """
  def refresh(table \\ @table, key, fun, min_age)

  def refresh(table, key, fun, min_age) do
    case :ets.whereis(table) do
      :undefined ->
        fun.()

      _ ->
        now = System.monotonic_time(:second)

        case :ets.lookup(table, key) do
          [{^key, value, _fun, inserted_at}] when now - inserted_at < min_age -> value
          _ -> compute(table, key, fun)
        end
    end
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
        compute(table, key, fun)
    end
  end

  defp refresh_async(table, key, fun) do
    if :ets.insert_new(table, {{:refreshing, key}}) do
      Task.start(fn ->
        try do
          store(table, key, fun.(), fun)
        after
          :ets.delete(table, {:refreshing, key})
        end
      end)
    end

    :ok
  end

  defp compute(table, key, fun) do
    case :ets.lookup(table, {:populating, key}) do
      [{_, leader}] ->
        wait_for(leader, table, key, fun)

      [] ->
        {worker, ref} =
          spawn_monitor(fn ->
            receive do
              :proceed ->
                result =
                  try do
                    value = fun.()
                    store(table, key, value, fun)
                    {:value, value}
                  catch
                    kind, reason -> {:raise, kind, reason, __STACKTRACE__}
                  after
                    :ets.delete(table, {:populating, key})
                  end

                exit({:shutdown, result})

              :abort ->
                :ok
            end
          end)

        if :ets.insert_new(table, {{:populating, key}, worker}) do
          send(worker, :proceed)
          await(ref, table, key, fun)
        else
          Process.demonitor(ref, [:flush])
          send(worker, :abort)

          case :ets.lookup(table, {:populating, key}) do
            [{_, leader}] -> wait_for(leader, table, key, fun)
            [] -> fetch(table, key, fun, :infinity)
          end
        end
    end
  end

  # The worker hands its result to every caller waiting on it through its exit
  # reason, so an error that isn't cached and an exception reach them all
  # without anyone computing again. A leader that was gone before we looked at
  # it has stored its value, or left nothing and this caller computes it.
  defp wait_for(pid, table, key, fun), do: await(Process.monitor(pid), table, key, fun)

  defp await(ref, table, key, fun) do
    receive do
      {:DOWN, ^ref, _, _, {:shutdown, {:value, value}}} ->
        value

      {:DOWN, ^ref, _, _, {:shutdown, {:raise, kind, reason, stacktrace}}} ->
        :erlang.raise(kind, reason, stacktrace)

      {:DOWN, ^ref, _, _, _reason} ->
        fetch(table, key, fun, :infinity)
    end
  end

  # An error goes back to the callers that asked for it but is never cached, so
  # the next fetch tries again instead of serving the failure, or replacing a
  # good value with it, for the whole TTL.
  defp store(_table, _key, {:error, _reason}, _fun), do: true

  defp store(table, key, value, fun),
    do: :ets.insert(table, {key, value, fun, System.monotonic_time(:second)})
end
