defmodule Hexpm.PromEx.Plugins.EctoTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Ecto, as: Plugin
  alias PromEx.Plugins.Ecto, as: Upstream

  @opts [otp_app: :hexpm, repos: [Hexpm.RepoBase]]

  @times [
    [:hexpm, :prom_ex, :ecto, :repo, :query, :idle, :time, :milliseconds],
    [:hexpm, :prom_ex, :ecto, :repo, :query, :queue, :time, :milliseconds],
    [:hexpm, :prom_ex, :ecto, :repo, :query, :decode, :time, :milliseconds],
    [:hexpm, :prom_ex, :ecto, :repo, :query, :execution, :time, :milliseconds],
    [:hexpm, :prom_ex, :ecto, :repo, :query, :total, :time, :milliseconds]
  ]

  @results [:hexpm, :prom_ex, :ecto, :repo, :query, :results, :returned]

  defp metrics(module) do
    @opts |> module.event_metrics() |> List.wrap() |> Enum.flat_map(& &1.metrics)
  end

  defp buckets(module) do
    Map.new(metrics(module), &{&1.name, &1.reporter_options[:buckets]})
  end

  test "returns the upstream metrics under the upstream names and groups" do
    ours = List.wrap(Plugin.event_metrics(@opts))
    upstream = List.wrap(Upstream.event_metrics(@opts))

    assert Enum.map(ours, & &1.group_name) == Enum.map(upstream, & &1.group_name)
    assert Enum.map(metrics(Plugin), & &1.name) == Enum.map(metrics(Upstream), & &1.name)
  end

  test "resolves query times below the upstream floor and keeps the alert's boundary" do
    ours = buckets(Plugin)
    upstream = buckets(Upstream)

    for name <- @times do
      buckets = ours[name]

      assert Enum.min(buckets) < 1, "#{inspect(name)} needs a sub-millisecond bucket"

      assert Enum.count(buckets, &(&1 < Enum.min(upstream[name]))) >= 3,
             "#{inspect(name)} needs several buckets below the upstream floor"

      assert 250 in buckets, "#{inspect(name)} needs 250ms for DbCheckoutWaitHigh"
      assert length(buckets) <= 12
      assert buckets == Enum.sort(buckets)
    end
  end

  test "counts selects of every package and release in a finite bucket" do
    buckets = buckets(Plugin)[@results]

    assert List.starts_with?(buckets, buckets(Upstream)[@results])
    assert Enum.max(buckets) >= 1_000_000
    assert buckets == Enum.sort(buckets)
  end

  test "leaves every other upstream metric unchanged" do
    rebucketed = [@results | @times]

    for {upstream, ours} <- Enum.zip(metrics(Upstream), metrics(Plugin)) do
      if upstream.name in rebucketed do
        assert %{ours | reporter_options: upstream.reporter_options} == upstream
      else
        assert ours == upstream
      end
    end
  end
end
