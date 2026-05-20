defmodule Hexpm.CacheTest do
  use ExUnit.Case, async: true
  alias Hexpm.Cache

  setup context do
    table = context.test
    Cache.start(table)
    on_exit(fn -> :ets.whereis(table) != :undefined && :ets.delete(table) end)
    %{table: table}
  end

  test "fetch populates on first call and returns cached on subsequent calls", %{table: table} do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert Cache.fetch(table, :key, fun, :infinity) == 1
    assert Cache.fetch(table, :key, fun, :infinity) == 1
    assert :counters.get(counter, 1) == 1
  end

  test "fetch falls through to fun when cache table is missing" do
    assert Cache.fetch(:no_such_cache, :key, fn -> :fallback end, :infinity) == :fallback
  end

  test "fetch with TTL serves stale value and refreshes asynchronously", %{table: table} do
    counter = :counters.new(1, [])

    fun = fn ->
      Process.sleep(100)
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert Cache.fetch(table, :key, fun, 60) == 1

    [{:key, _value, stored_fun, _ts}] = :ets.lookup(table, :key)
    :ets.insert(table, {:key, 1, stored_fun, System.monotonic_time(:second) - 120})

    tasks = for _ <- 1..10, do: Task.async(fn -> Cache.fetch(table, :key, fun, 60) end)
    assert Enum.map(tasks, &Task.await/1) == List.duplicate(1, 10)

    Process.sleep(200)

    assert :counters.get(counter, 1) == 2
    assert Cache.fetch(table, :key, fun, 60) == 2
  end

  test "invalidate removes a cached entry so the next fetch recomputes", %{table: table} do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert Cache.fetch(table, :key, fun, :infinity) == 1
    assert Cache.fetch(table, :key, fun, :infinity) == 1

    assert Cache.invalidate(table, :key) == :ok
    assert :ets.lookup(table, :key) == []

    assert Cache.fetch(table, :key, fun, :infinity) == 2
  end

  test "invalidate is a no-op when the cache table is missing" do
    assert Cache.invalidate(:no_such_cache, :key) == :ok
  end

  test "concurrent cold readers run the fun exactly once", %{table: table} do
    counter = :counters.new(1, [])
    {:ok, gate} = Agent.start_link(fn -> nil end)

    fun = fn ->
      Agent.get(gate, & &1, :infinity)
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    tasks = for _ <- 1..20, do: Task.async(fn -> Cache.fetch(table, :key, fun, :infinity) end)
    Process.sleep(10)
    Agent.update(gate, fn _ -> :go end)

    results = Enum.map(tasks, &Task.await/1)

    assert :counters.get(counter, 1) == 1
    assert Enum.uniq(results) == [1]
  end
end
