defmodule Hexpm.CacheTest do
  use ExUnit.Case, async: true
  alias Hexpm.Cache

  test "fetch populates on first call and returns cached on subsequent calls" do
    {:ok, pid} = Cache.start_link(name: :cache_test_fetch, interval: 60_000)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert Cache.fetch(:cache_test_fetch, :key, fun) == 1
    assert Cache.fetch(:cache_test_fetch, :key, fun) == 1
    assert :counters.get(counter, 1) == 1
  end

  test "refresh re-runs registered fns" do
    {:ok, pid} = Cache.start_link(name: :cache_test_refresh, interval: 60_000)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert Cache.fetch(:cache_test_refresh, :key, fun) == 1
    :ok = Cache.refresh(:cache_test_refresh)
    assert Cache.fetch(:cache_test_refresh, :key, fun) == 2
  end

  test "fetch falls through to fun when cache not started" do
    assert Cache.fetch(:no_such_cache, :key, fn -> :fallback end) == :fallback
  end
end
