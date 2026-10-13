defmodule Hexpm.PromEx.Plugins.PhoenixTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Phoenix, as: Plugin
  alias PromEx.Plugins.Phoenix, as: Upstream

  @opts [otp_app: :hexpm, router: HexpmWeb.Router, endpoint: HexpmWeb.Endpoint]

  @http_metrics [
    [:hexpm, :prom_ex, :phoenix, :http, :request, :duration, :milliseconds],
    [:hexpm, :prom_ex, :phoenix, :http, :response, :size, :bytes],
    [:hexpm, :prom_ex, :phoenix, :http, :requests, :total]
  ]

  defp metrics(module) do
    @opts |> module.event_metrics() |> List.wrap() |> Enum.flat_map(& &1.metrics)
  end

  defp labels(metric, conn) do
    %{conn: conn} |> metric.tag_values.() |> Map.take(metric.tags)
  end

  defp conn(method, url) do
    method |> Plug.Test.conn(url) |> Plug.Conn.resp(200, "")
  end

  test "returns the upstream metrics under the upstream names and groups" do
    ours = List.wrap(Plugin.event_metrics(@opts))
    upstream = List.wrap(Upstream.event_metrics(@opts))

    assert Enum.map(ours, & &1.group_name) == Enum.map(upstream, & &1.group_name)
    assert Enum.map(metrics(Plugin), & &1.name) == Enum.map(metrics(Upstream), & &1.name)
  end

  test "drops the host label from the HTTP metrics and keeps the other labels and buckets" do
    pairs = Enum.zip(metrics(Upstream), metrics(Plugin))

    for {upstream, ours} <- pairs do
      if upstream.name in @http_metrics do
        assert :host in upstream.tags
        assert ours.tags == List.delete(upstream.tags, :host)
        assert ours.reporter_options == upstream.reporter_options
        assert %{ours | tags: upstream.tags, tag_values: upstream.tag_values} == upstream
      else
        assert ours == upstream
      end
    end
  end

  test "labels a request by route and method whatever host it names" do
    for metric <- metrics(Plugin), metric.name in @http_metrics do
      for host <- ["hex.pm", "203.0.113.5"] do
        assert labels(metric, conn("GET", "http://#{host}/docs/usage")) == %{
                 status: 200,
                 method: "GET",
                 path: "/docs/usage",
                 controller: "HexpmWeb.DocsController",
                 action: :usage
               }
      end
    end
  end

  test "labels a method HTTP doesn't define as OTHER" do
    for metric <- metrics(Plugin), metric.name in @http_metrics do
      for method <- ~w(GET HEAD POST PUT PATCH DELETE OPTIONS) do
        assert labels(metric, conn(method, "http://hex.pm/")).method == method
      end

      for method <- ~w(AHSN SSTP_DUPLEX_POST PROPFIND) do
        assert labels(metric, conn(method, "http://hex.pm/")).method == "OTHER"
      end
    end
  end
end
