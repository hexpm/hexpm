defmodule Hexpm.PromEx.Plugins.EctoLatencyTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.EctoLatency

  defp metrics() do
    EctoLatency.event_metrics(otp_app: :hexpm).metrics
  end

  test "reports queue and query time off the repo's telemetry event" do
    assert [queue, query] = metrics()

    assert queue.name == [:hexpm, :prom_ex, :ecto_latency, :queue, :time, :milliseconds]
    assert query.name == [:hexpm, :prom_ex, :ecto_latency, :query, :time, :milliseconds]

    for metric <- [queue, query] do
      assert metric.event_name ==
               Keyword.fetch!(Hexpm.RepoBase.config(), :telemetry_prefix) ++ [:query]

      assert metric.unit == :millisecond
    end
  end

  test "resolves below the 10ms floor the upstream Ecto plugin reports" do
    for metric <- metrics() do
      buckets = metric.reporter_options[:buckets]

      assert Enum.min(buckets) < 1,
             "#{inspect(metric.name)} needs sub-millisecond buckets to be worth adding"

      assert Enum.count(buckets, &(&1 < 10)) >= 5,
             "#{inspect(metric.name)} needs several buckets below the upstream floor of 10ms"

      assert buckets == Enum.sort(buckets)
    end
  end

  test "does not collide with the upstream Ecto plugin's metric names" do
    upstream =
      PromEx.Plugins.Ecto.event_metrics(otp_app: :hexpm, repos: [Hexpm.RepoBase])
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)
      |> MapSet.new(& &1.name)

    for metric <- metrics() do
      refute MapSet.member?(upstream, metric.name)
    end
  end
end
