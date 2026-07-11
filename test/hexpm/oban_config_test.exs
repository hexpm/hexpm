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
  end

  test "production schedules periodic work and retains completed jobs for seven days" do
    prod = Config.Reader.read!("config/prod.exs", env: :prod)
    oban = prod[:hexpm][Oban]

    assert oban[:peer] == Oban.Peers.Database

    assert {Oban.Plugins.Cron, cron_opts} =
             Enum.find(oban[:plugins], &match?({Oban.Plugins.Cron, _}, &1))

    assert cron_opts[:timezone] == "Etc/UTC"

    assert cron_opts[:crontab] == [
             {"* * * * *", Hexpm.Billing.Report},
             {"*/30 * * * *", Hexpm.Security.Updater}
           ]

    assert {Oban.Plugins.Pruner, [max_age: 604_800]} in oban[:plugins]
    assert Oban.Plugins.Lifeline in oban[:plugins]
  end
end
