defmodule Hexpm.PromEx.Plugins.HexpmOrganizationMetricsTest do
  use Hexpm.DataCase, async: true

  import ExUnit.CaptureLog

  alias Hexpm.PromEx.Plugins.Hexpm, as: Plugin

  setup do
    ref = make_ref()
    parent = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:hexpm, :organizations, :billing],
      fn _event, measurements, _metadata, _config -> send(parent, {ref, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)
    %{ref: ref}
  end

  test "emits the organization counts", %{ref: ref} do
    insert(:organization, billing_active: true)

    assert :ok = Plugin.execute_organization_metrics()

    assert_receive {^ref, %{active: active, inactive: _, scheduled: 0}}
    assert active >= 1
  end

  # A process the sandbox has not let in (spawned plainly, so it carries no
  # caller) gets the same kind of failure a poll gets before the repo is up:
  # not a database error, and it must not reach telemetry_poller.
  test "skips the reading when the database cannot be read", %{ref: ref} do
    parent = self()

    log =
      capture_log(fn ->
        spawn(fn -> send(parent, {:result, Plugin.execute_organization_metrics()}) end)
        assert_receive {:result, :ok}, 5_000
      end)

    assert log =~ "organization metrics skipped"
    refute_received {^ref, _}
  end
end
