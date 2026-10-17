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

  test "fetch returns an error without caching it", %{table: table} do
    {:ok, results} = Agent.start_link(fn -> [{:error, :timeout}, :ok] end)
    fun = fn -> Agent.get_and_update(results, fn [result | rest] -> {result, rest} end) end

    assert Cache.fetch(table, :key, fun, :infinity) == {:error, :timeout}
    assert Cache.fetch(table, :key, fun, :infinity) == :ok
    assert Cache.fetch(table, :key, fun, :infinity) == :ok
  end

  test "a stale value is kept when its refresh returns an error", %{table: table} do
    assert Cache.fetch(table, :key, fn -> :good end, 60) == :good
    [{:key, :good, stored_fun, _ts}] = :ets.lookup(table, :key)
    :ets.insert(table, {:key, :good, stored_fun, System.monotonic_time(:second) - 120})

    assert Cache.fetch(table, :key, fn -> {:error, :timeout} end, 60) == :good
    wait_until(fn -> :ets.lookup(table, {:refreshing, :key}) == [] end)

    assert [{:key, :good, _fun, _ts}] = :ets.lookup(table, :key)
  end

  test "an exception reaches every waiting caller and runs the fun once", %{table: table} do
    counter = :counters.new(1, [])
    {:ok, gate} = Agent.start_link(fn -> nil end)

    fun = fn ->
      Agent.get(gate, & &1, :infinity)
      :counters.add(counter, 1, 1)
      raise "unavailable"
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          try do
            Cache.fetch(table, :key, fun, :infinity)
          rescue
            error in RuntimeError -> error.message
          end
        end)
      end

    Process.sleep(10)
    Agent.update(gate, fn _ -> :go end)

    assert Enum.map(tasks, &Task.await/1) == List.duplicate("unavailable", 5)
    assert :counters.get(counter, 1) == 1
    assert :ets.lookup(table, :key) == []
  end

  test "refresh recomputes a value older than the minimum age", %{table: table} do
    assert Cache.fetch(table, :key, fn -> 1 end, :infinity) == 1
    assert Cache.refresh(table, :key, fn -> 2 end, 60) == 1

    [{:key, 1, stored_fun, _ts}] = :ets.lookup(table, :key)
    :ets.insert(table, {:key, 1, stored_fun, System.monotonic_time(:second) - 61})

    assert Cache.refresh(table, :key, fn -> 2 end, 60) == 2
    assert Cache.fetch(table, :key, fn -> 3 end, :infinity) == 2
  end

  test "refresh keeps the cached value when the new one is an error", %{table: table} do
    assert Cache.fetch(table, :key, fn -> :good end, :infinity) == :good
    [{:key, :good, stored_fun, _ts}] = :ets.lookup(table, :key)
    :ets.insert(table, {:key, :good, stored_fun, System.monotonic_time(:second) - 61})

    assert Cache.refresh(table, :key, fn -> {:error, :timeout} end, 60) == {:error, :timeout}
    assert Cache.fetch(table, :key, fn -> :other end, :infinity) == :good
  end

  test "refresh falls through to fun when cache table is missing" do
    assert Cache.refresh(:no_such_cache, :key, fn -> :fallback end, 60) == :fallback
  end

  defp wait_until(fun, attempts \\ 100) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition never held")

      true ->
        Process.sleep(5)
        wait_until(fun, attempts - 1)
    end
  end
end
