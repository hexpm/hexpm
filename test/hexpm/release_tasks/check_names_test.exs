defmodule Hexpm.ReleaseTasks.CheckNamesTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  import Swoosh.TestAssertions

  alias Hexpm.CronMonitor.SentryMock
  alias Hexpm.ReleaseTasks.CheckNames

  @date ~D[2026-07-20]

  setup :verify_on_exit!

  setup do
    insert(:package, name: "phoenix", inserted_at: at(Date.add(@date, -2)))
    insert(:package, name: "phoenics", inserted_at: at(@date))
    insert(:package, name: "poison", inserted_at: at(Date.add(@date, -2)))
    insert(:package, name: "poizon", inserted_at: at(Date.add(@date, -1)))
    insert(:package, name: "hector", inserted_at: at(Date.add(@date, -2)))
    insert(:package, name: "hectro", inserted_at: at(Date.add(@date, 1)))

    :ok
  end

  test "finds typosquats from a fixed UTC date interval" do
    assert CheckNames.find_candidates(2, @date) == [["phoenics", "phoenix", 2]]
  end

  test "scheduled jobs use the UTC date from scheduled_at" do
    app_env(:hexpm, :levenshtein_threshold, "2")
    expect_monitor()

    assert :ok =
             perform_job(CheckNames, %{},
               scheduled_at: DateTime.new!(@date, ~T[00:30:00], "Etc/UTC")
             )

    assert_email_sent(subject: "[TYPOSQUAT CANDIDATES]")
  end

  test "explicit dates support manual backfills" do
    app_env(:hexpm, :levenshtein_threshold, 2)
    expect_monitor()

    assert :ok =
             perform_job(CheckNames, %{"date" => Date.to_iso8601(@date)},
               scheduled_at: DateTime.new!(Date.add(@date, 10), ~T[00:30:00], "Etc/UTC")
             )

    assert_email_sent(subject: "[TYPOSQUAT CANDIDATES]")
  end

  test "invalid dates cancel without retrying" do
    assert {:cancel, {:invalid_date, "not-a-date"}} =
             perform_job(CheckNames, %{"date" => "not-a-date"})
  end

  defp expect_monitor do
    app_env(:hexpm, :sentry_impl, SentryMock)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts[:status] == :in_progress
      assert opts[:monitor_slug] == "hexpm-check-names"

      assert opts[:monitor_config] == [
               schedule: [type: :crontab, value: "30 0 * * *"],
               timezone: "Etc/UTC"
             ]

      {:ok, "check-in-id"}
    end)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               check_in_id: "check-in-id",
               status: :ok,
               monitor_slug: "hexpm-check-names"
             ]

      :ignored
    end)
  end

  defp at(date), do: DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
end
