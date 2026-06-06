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
end
