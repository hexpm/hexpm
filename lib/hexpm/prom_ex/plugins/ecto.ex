defmodule Hexpm.PromEx.Plugins.Ecto do
  @moduledoc """
  `PromEx.Plugins.Ecto` with query buckets that resolve the queries run here.

  The upstream plugin hardcodes its buckets and offers no option to change
  them. Its time histograms start at 10ms (5ms for decode time), and over 7
  days 99.7% of the query execution times and 99.999% of the queue times
  here fell in that first bucket, so their heatmaps showed one band. The idle,
  queue, decode, execution and total time histograms start at 0.5ms instead
  and keep 250ms, which `DbCheckoutWaitHigh` compares the queue time's p99
  against. The execution and total time series are per source and command on
  every pod, so they stay at a dozen buckets.

  Its results returned histogram ends at 1,000 rows, and loading every
  package, release or organization returns more, so its buckets go on to
  1,000,000 rows.

  The upstream metrics are returned under their own names with only those
  buckets replaced, so the upstream Ecto dashboard keeps working.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event
  alias Telemetry.Metrics.Distribution

  @time_buckets [0.5, 1, 2.5, 5, 10, 25, 50, 250, 1_000, 2_500, 10_000, 30_000]
  @results_buckets [5, 10, 50, 100, 500, 1_000, 10_000, 100_000, 1_000_000]

  @rebucketed [
    {[:repo, :query, :idle, :time, :milliseconds], @time_buckets},
    {[:repo, :query, :queue, :time, :milliseconds], @time_buckets},
    {[:repo, :query, :decode, :time, :milliseconds], @time_buckets},
    {[:repo, :query, :execution, :time, :milliseconds], @time_buckets},
    {[:repo, :query, :total, :time, :milliseconds], @time_buckets},
    {[:repo, :query, :results, :returned], @results_buckets}
  ]

  @impl true
  def event_metrics(opts) do
    opts
    |> PromEx.Plugins.Ecto.event_metrics()
    |> Enum.map(&rebucket/1)
  end

  defp rebucket(%Event{metrics: metrics} = event) do
    %{event | metrics: Enum.map(metrics, &rebucket_metric/1)}
  end

  defp rebucket_metric(%Distribution{name: name, reporter_options: options} = metric) do
    case Enum.find(@rebucketed, fn {suffix, _buckets} -> List.ends_with?(name, suffix) end) do
      {_suffix, buckets} -> %{metric | reporter_options: Keyword.put(options, :buckets, buckets)}
      nil -> metric
    end
  end

  defp rebucket_metric(metric), do: metric
end
