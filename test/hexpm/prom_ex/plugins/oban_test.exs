defmodule Hexpm.PromEx.Plugins.ObanTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Oban, as: Plugin
  alias PromEx.Plugins.Oban, as: Upstream

  @opts [otp_app: :hexpm, poll_rate: :timer.minutes(1)]

  @rebucketed [
    [:hexpm, :prom_ex, :oban, :job, :processing, :duration, :milliseconds],
    [:hexpm, :prom_ex, :oban, :job, :queue, :time, :milliseconds],
    [:hexpm, :prom_ex, :oban, :job, :exception, :duration, :milliseconds],
    [:hexpm, :prom_ex, :oban, :job, :exception, :queue, :time, :milliseconds]
  ]

  defp metrics(module) do
    @opts |> module.event_metrics() |> List.wrap() |> Enum.flat_map(& &1.metrics)
  end

  test "returns the upstream metrics under the upstream names and groups" do
    ours = List.wrap(Plugin.event_metrics(@opts))
    upstream = List.wrap(Upstream.event_metrics(@opts))

    assert Enum.map(ours, & &1.group_name) == Enum.map(upstream, & &1.group_name)
    assert Enum.map(metrics(Plugin), & &1.name) == Enum.map(metrics(Upstream), & &1.name)
    assert Plugin.polling_metrics(@opts) == Upstream.polling_metrics(@opts)
  end

  test "extends the job duration and queue time buckets past the upstream ceiling" do
    ours = Map.new(metrics(Plugin), &{&1.name, &1})
    upstream = Map.new(metrics(Upstream), &{&1.name, &1})

    for name <- @rebucketed do
      buckets = ours[name].reporter_options[:buckets]
      upstream_buckets = upstream[name].reporter_options[:buckets]

      assert List.starts_with?(buckets, upstream_buckets),
             "#{inspect(name)} should keep the upstream buckets so existing panels keep their resolution"

      assert Enum.max(buckets) >= longest_worker_timeout(),
             "#{inspect(name)} needs a bucket that holds the longest-running worker"

      assert buckets == Enum.sort(buckets)
    end
  end

  defp longest_worker_timeout() do
    :hexpm
    |> Application.spec(:modules)
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__opts__, 0)))
    |> Enum.map(& &1.timeout(%Oban.Job{}))
    |> Enum.filter(&is_integer/1)
    |> Enum.max()
  end

  test "leaves every other upstream metric unchanged" do
    pairs = Enum.zip(metrics(Upstream), metrics(Plugin))

    for {upstream, ours} <- pairs do
      if upstream.name in @rebucketed do
        assert %{ours | reporter_options: upstream.reporter_options} == upstream
      else
        assert ours == upstream
      end
    end
  end
end
