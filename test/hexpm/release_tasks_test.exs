defmodule Hexpm.ReleaseTasksTest do
  use ExUnit.Case, async: true

  alias Hexpm.ReleaseTasks

  test "monitor/3 runs the task and returns :ok on success" do
    parent = self()

    assert ReleaseTasks.monitor("test-monitor", "0 1 * * *", fn -> send(parent, :ran) end) == :ok
    assert_received :ran
  end

  test "monitor/3 returns :error when the task raises" do
    assert ReleaseTasks.monitor("test-monitor", "0 1 * * *", fn -> raise "boom" end) == :error
  end

  test "scheduled tasks are skipped in read-only mode" do
    parent = self()

    assert ReleaseTasks.run_scheduled("test-task", fn -> send(parent, :ran) end, true) ==
             :skipped

    refute_received :ran
  end

  test "scheduled tasks run in write mode" do
    parent = self()

    assert ReleaseTasks.run_scheduled("test-task", fn -> send(parent, :ran) end, false) == :ran
    assert_received :ran
  end
end
