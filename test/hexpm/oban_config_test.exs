defmodule Hexpm.ObanConfigTest do
  use ExUnit.Case, async: true

  test "test configuration uses manual execution" do
    config = Application.fetch_env!(:hexpm, Oban)

    assert config[:testing] == :manual
    assert config[:queues] == false
    assert config[:plugins] == false
    assert config[:shutdown_grace_period] == 300_000
  end

  test "periodic workers use the periodic queue with retries and incomplete uniqueness" do
    for worker <- [Hexpm.Billing.Report, Hexpm.Security.Updater] do
      assert worker.__opts__()[:queue] == :periodic
      assert worker.__opts__()[:max_attempts] == 5
      assert worker.__opts__()[:unique] == [period: :infinity, states: :incomplete]
    end

    assert Hexpm.Billing.Report.timeout(%Oban.Job{}) == 20_000
    assert Hexpm.Security.Updater.timeout(%Oban.Job{}) == 300_000

    for {worker, queue, timeout} <- [
          {Hexpm.ReleaseTasks.CheckNames, :periodic, 600_000},
          {Hexpm.ReleaseTasks.Stats, :heavy, 3_600_000},
          {Hexpm.ReleaseTasks.PurgeExpiredRecords, :periodic, 1_800_000}
        ] do
      assert worker.__opts__()[:queue] == queue
      assert worker.__opts__()[:max_attempts] == 5

      assert worker.__opts__()[:unique] == [
               period: :infinity,
               states: :incomplete,
               fields: [:worker]
             ]

      assert worker.timeout(%Oban.Job{}) == timeout
    end

    assert Hexpm.Emails.OutboxReconciler.__opts__()[:queue] == :periodic

    # One attempt paired with incomplete uniqueness: a retryable job counts as
    # incomplete, so retrying in place would stop cron inserting the next tick
    # for the whole backoff and the outbox would go unswept for hours.
    assert Hexpm.Emails.OutboxReconciler.__opts__()[:max_attempts] == 1

    assert Hexpm.Emails.OutboxReconciler.__opts__()[:unique] == [
             period: :infinity,
             states: :incomplete
           ]

    assert Hexpm.Emails.OutboxWorker.timeout(%Oban.Job{}) == 30_000

    for worker <- [
          Hexpm.Diff.Worker,
          Hexpm.Hexdocs.Workers.Upload,
          Hexpm.Hexdocs.Workers.Search,
          Hexpm.Hexdocs.Workers.Delete,
          Hexpm.Hexdocs.Workers.Sitemap,
          Hexpm.Preview.Workers.Upload,
          Hexpm.Preview.Workers.Delete
        ] do
      assert worker.__opts__()[:queue] == :heavy
      assert worker.__opts__()[:max_attempts] == 5

      assert worker.__opts__()[:unique] == [
               period: :infinity,
               states: :incomplete,
               fields: [:worker, :args]
             ]

      assert worker.timeout(%Oban.Job{}) == 270_000
    end
  end

  test "production schedules periodic work and keeps failures far longer than successes" do
    prod = Config.Reader.read!("config/prod.exs", env: :prod)
    oban = prod[:hexpm][Oban]

    assert oban[:peer] == Oban.Peers.Database

    assert {Oban.Plugins.Cron, cron_opts} =
             Enum.find(oban[:plugins], &match?({Oban.Plugins.Cron, _}, &1))

    assert cron_opts[:timezone] == "Etc/UTC"

    assert cron_opts[:crontab] == [
             {"* * * * *", Hexpm.Billing.Report},
             {"* * * * *", Hexpm.Emails.OutboxReconciler},
             {"*/30 * * * *", Hexpm.Security.Updater},
             {"30 0 * * *", Hexpm.ReleaseTasks.CheckNames},
             {"0 1 * * *", Hexpm.ReleaseTasks.Stats},
             {"0 2 * * *", Hexpm.ReleaseTasks.PurgeExpiredRecords},
             {"15 3 * * *", Hexpm.Accounts.OrganizationDomains.RecheckWorker},
             {"45 3 * * *", Hexpm.Accounts.SSO.EnforcementWorker}
           ]

    assert {Hexpm.Oban.Pruner, [max_age: 259_200, discarded_max_age: 31_536_000]} in oban[
             :plugins
           ]

    assert {Oban.Plugins.Lifeline, [interval: 60_000, rescue_after: 5_400_000]} in oban[:plugins]
  end

  test "orphan rescue waits longer than any worker may legitimately run" do
    prod = Config.Reader.read!("config/prod.exs", env: :prod)

    assert {Oban.Plugins.Lifeline, lifeline} =
             Enum.find(prod[:hexpm][Oban][:plugins], &match?({Oban.Plugins.Lifeline, _}, &1))

    workers =
      :hexpm
      |> Application.spec(:modules)
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__opts__, 0)))
      |> Enum.map(&{&1, &1.timeout(%Oban.Job{})})
      |> Enum.filter(&is_integer(elem(&1, 1)))

    assert {Hexpm.ReleaseTasks.Stats, 3_600_000} in workers

    for {worker, timeout} <- workers do
      assert lifeline[:rescue_after] > timeout,
             "#{inspect(worker)} may run for #{timeout}ms, but Lifeline returns a job to " <>
               "available after #{lifeline[:rescue_after]}ms whether or not it is still " <>
               "running, so it would be picked up a second time mid-flight"
    end
  end
end
