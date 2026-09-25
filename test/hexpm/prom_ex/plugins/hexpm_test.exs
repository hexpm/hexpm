defmodule Hexpm.PromEx.Plugins.HexpmTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Hexpm, as: Plugin

  test "counts API authentication by scheme and result" do
    [counter] =
      [otp_app: :hexpm]
      |> Plugin.event_metrics()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.filter(&(&1.event_name == [:hexpm, :api, :authenticate]))

    assert %Telemetry.Metrics.Counter{tags: [:scheme, :result]} = counter
  end

  test "measures the number of connected nodes" do
    ref = make_ref()
    parent = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:hexpm, :cluster, :connected_nodes],
      fn _event, measurements, _metadata, _config -> send(parent, {ref, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)

    Plugin.execute_cluster_metrics()

    assert_receive {^ref, %{count: count}}
    assert count == length(Node.list())
  end

  test "polls the connected node count as a gauge" do
    polling =
      [otp_app: :hexpm]
      |> Plugin.polling_metrics()
      |> Enum.find(&(&1.measurements_mfa == {Plugin, :execute_cluster_metrics, []}))

    assert [%Telemetry.Metrics.LastValue{name: [:hexpm, :cluster, :connected_nodes]}] =
             polling.metrics
  end

  test "polls the organization billing states once a minute" do
    polling =
      [otp_app: :hexpm]
      |> Plugin.polling_metrics()
      |> Enum.find(&(&1.measurements_mfa == {Plugin, :execute_organization_metrics, []}))

    assert polling.poll_rate == :timer.minutes(1)

    assert Enum.map(polling.metrics, & &1.name) == [
             [:hexpm, :organizations, :active],
             [:hexpm, :organizations, :inactive],
             [:hexpm, :organizations, :scheduled]
           ]
  end

  test "sums the billing state changes and each step of the deletion run" do
    metrics =
      [otp_app: :hexpm]
      |> Plugin.event_metrics()
      |> Enum.flat_map(& &1.metrics)

    assert %Telemetry.Metrics.Sum{tags: [:billing_active]} =
             Enum.find(
               metrics,
               &(&1.event_name == [:hexpm, :billing, :organization_state_changed])
             )

    steps =
      metrics
      |> Enum.filter(&(&1.event_name == [:hexpm, :organization_deletions, :run]))
      |> Enum.map(& &1.measurement)

    assert steps == [:cleared, :scheduled, :reminded, :deleted, :skipped, :failed]
  end
end
