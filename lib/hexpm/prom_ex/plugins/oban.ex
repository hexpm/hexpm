defmodule Hexpm.PromEx.Plugins.Oban do
  @moduledoc """
  `PromEx.Plugins.Oban` with job duration buckets that cover the jobs run here.

  The upstream plugin hardcodes `[10, 100, 500, 1_000, 5_000, 20_000]` for the
  job processing and queue time histograms and offers no option to change them.
  A purge job may run for five minutes, a full registry build for thirty and
  the stats job for an hour, so upstream's histograms put most of what runs
  here in the overflow bucket.

  The upstream metrics are returned under their own names with only those
  buckets replaced, so the upstream Oban dashboard keeps working.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event
  alias Telemetry.Metrics.Distribution

  @buckets [10, 100, 500, 1_000, 5_000, 20_000, 60_000, 300_000, 900_000, 3_600_000]

  @rebucketed [
    [:job, :processing, :duration, :milliseconds],
    [:job, :queue, :time, :milliseconds],
    [:job, :exception, :duration, :milliseconds],
    [:job, :exception, :queue, :time, :milliseconds]
  ]

  @impl true
  def event_metrics(opts) do
    opts
    |> PromEx.Plugins.Oban.event_metrics()
    |> Enum.map(&rebucket/1)
  end

  @impl true
  def polling_metrics(opts), do: PromEx.Plugins.Oban.polling_metrics(opts)

  defp rebucket(%Event{metrics: metrics} = event) do
    %{event | metrics: Enum.map(metrics, &rebucket_metric/1)}
  end

  defp rebucket_metric(%Distribution{name: name, reporter_options: options} = metric) do
    if Enum.any?(@rebucketed, &List.ends_with?(name, &1)) do
      %{metric | reporter_options: Keyword.put(options, :buckets, @buckets)}
    else
      metric
    end
  end

  defp rebucket_metric(metric), do: metric
end
