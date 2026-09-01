defmodule Hexpm.PromEx.Plugins.HexpmTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Hexpm, as: Plugin

  test "mint success tags keep provider cardinality bounded" do
    assert Plugin.mint_success_tags(%{provider: "github", package_id: 123}) == %{
             provider: "github"
           }

    assert Plugin.mint_success_tags(%{}) == %{provider: "unknown"}
  end

  test "mint failure tags surface the error reason" do
    assert Plugin.mint_failure_tags(%{reason: :token_replayed}) == %{reason: :token_replayed}
    assert Plugin.mint_failure_tags(%{}) == %{reason: "unknown"}
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
    [polling] = [otp_app: :hexpm] |> Plugin.polling_metrics() |> List.wrap()

    assert polling.measurements_mfa == {Plugin, :execute_cluster_metrics, []}

    assert [%Telemetry.Metrics.LastValue{name: [:hexpm, :cluster, :connected_nodes]}] =
             polling.metrics
  end
end
