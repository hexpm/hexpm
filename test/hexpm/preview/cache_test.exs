defmodule Hexpm.Preview.CacheTest do
  use ExUnit.Case, async: false

  alias Hexpm.Preview.Cache

  @cache __MODULE__.Store

  setup do
    start_supervised!({Cache, name: @cache, max_entries: 2, ttl: 20})
    :ok
  end

  test "reuses cached values" do
    assert Cache.fetch(@cache, :key, fn -> :first end) == :first
    assert Cache.fetch(@cache, :key, fn -> :second end) == :first
  end

  test "does not cache missing values" do
    assert Cache.fetch(@cache, :key, fn -> nil end) == nil
    assert Cache.fetch(@cache, :key, fn -> :available end) == :available
  end

  test "bounds the number of entries" do
    Cache.fetch(@cache, :one, fn -> 1 end)
    Cache.fetch(@cache, :two, fn -> 2 end)
    Cache.fetch(@cache, :three, fn -> 3 end)

    assert :ets.info(@cache, :size) == 2
  end

  test "expires entries" do
    assert Cache.fetch(@cache, :key, fn -> :first end) == :first
    Process.sleep(21)
    assert Cache.fetch(@cache, :key, fn -> :second end) == :second
  end
end
