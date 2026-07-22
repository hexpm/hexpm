defmodule Hexpm.CronMonitorTest do
  use ExUnit.Case, async: false

  import Mox

  alias Hexpm.CronMonitor
  alias Hexpm.CronMonitor.SentryMock

  setup :verify_on_exit!

  setup do
    previous = Application.get_env(:hexpm, :sentry_impl)
    Application.put_env(:hexpm, :sentry_impl, SentryMock)

    on_exit(fn ->
      if previous do
        Application.put_env(:hexpm, :sentry_impl, previous)
      else
        Application.delete_env(:hexpm, :sentry_impl)
      end
    end)
  end

  test "records successful check-ins and returns the result" do
    expect_check_ins(:ok)

    assert {:ok, :result} =
             CronMonitor.run("test-monitor", "0 1 * * *", fn -> {:ok, :result} end)
  end

  test "records failed check-ins and re-raises the failure" do
    expect_check_ins(:error)

    assert_raise RuntimeError, "boom", fn ->
      CronMonitor.run("test-monitor", "0 1 * * *", fn -> raise "boom" end)
    end
  end

  defp expect_check_ins(final_status) do
    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               status: :in_progress,
               monitor_slug: "test-monitor",
               monitor_config: [
                 schedule: [type: :crontab, value: "0 1 * * *"],
                 timezone: "Etc/UTC"
               ]
             ]

      {:ok, "check-in-id"}
    end)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               check_in_id: "check-in-id",
               status: final_status,
               monitor_slug: "test-monitor"
             ]

      :ignored
    end)
  end
end
