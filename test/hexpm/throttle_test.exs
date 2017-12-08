defmodule Hexpm.ThrottleTest do
  use ExUnit.Case, async: true
  alias Hexpm.Throttle

  setup context do
    {:ok, pid} = Throttle.start_link(rate: 5, unit: 100)
    {:ok, Map.put(context, :pid, pid)}
  end

  defp diff(start) do
    :erlang.monotonic_time(:milli_seconds) - start
  end

  test "throttle and then reset", context do
    # First time unit
    start = :erlang.monotonic_time(:milli_seconds)

    Throttle.wait(context.pid, 1)
    assert diff(start) < 10
    Throttle.wait(context.pid, 4)
    assert diff(start) < 10
    Throttle.wait(context.pid, 1)
    assert diff(start) > 90

    # Second time unit
    start = :erlang.monotonic_time(:milli_seconds)

    Throttle.wait(context.pid, 1)
    assert diff(start) < 10
  end

  test "reset based on time unit", context do
    # First time unit
    start = :erlang.monotonic_time(:milli_seconds)

    Throttle.wait(context.pid, 1)
    assert diff(start) < 10

    Process.sleep(110)

    # Second time unit
    start = :erlang.monotonic_time(:milli_seconds)

    Throttle.wait(context.pid, 5)
    assert diff(start) < 10
    Throttle.wait(context.pid, 1)
    assert diff(start) > 90
  end

  test "only churn through rate after reset", context do
    # First time unit
    start = :erlang.monotonic_time(:milli_seconds)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert diff(start) < 10
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert diff(start) < 10
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert diff(start) < 10
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert diff(start) < 10
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert diff(start) < 10
    end)

    Process.sleep(10)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(90, 110, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(90, 110, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(90, 110, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(90, 110, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(90, 110, diff(start))
    end)

    Process.sleep(10)

    # Third time unit
    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(190, 210, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(190, 210, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(190, 210, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(190, 210, diff(start))
    end)

    spawn_link(fn ->
      Throttle.wait(context.pid, 1)
      assert_in_delta(190, 210, diff(start))
    end)

    Process.sleep(300)
  end
end
