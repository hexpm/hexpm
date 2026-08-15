defmodule Hexpm.PromEx.Plugins.EctoLatency do
  @moduledoc """
  PromEx plugin for how long database work waits, at a resolution the upstream
  Ecto plugin cannot express.

  `PromEx.Plugins.Ecto` hardcodes `[10, 50, 250, 1_000, 5_000, 10_000]` for every
  duration it reports, and offers no option to change them. Almost all traffic
  here finishes inside the first bucket, so those histograms answer "under 10ms"
  and nothing finer, which is the wrong granularity for a pool that hands out
  connections in microseconds.

  Two measurements are worth separating when requests slow down: `queue_time` is
  how long a caller waited for a connection, `query_time` is how long the database
  took once it had one. A rise in the first without the second means the pool is
  the constraint; the reverse means the database is.
  """

  use PromEx.Plugin

  @buckets [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100, 500, 1_000]

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :ecto_latency))

    event_name =
      Hexpm.RepoBase.config() |> Keyword.fetch!(:telemetry_prefix) |> Kernel.++([:query])

    Event.build(:hexpm_ecto_latency_event_metrics, [
      distribution(
        metric_prefix ++ [:queue, :time, :milliseconds],
        event_name: event_name,
        measurement: :queue_time,
        description: "How long a caller waited to check out a database connection.",
        reporter_options: [buckets: @buckets],
        unit: {:native, :millisecond}
      ),
      distribution(
        metric_prefix ++ [:query, :time, :milliseconds],
        event_name: event_name,
        measurement: :query_time,
        description: "How long the database took to run the query.",
        reporter_options: [buckets: @buckets],
        unit: {:native, :millisecond}
      )
    ])
  end
end
