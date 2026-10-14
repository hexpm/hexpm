defmodule Hexpm.PromEx.Plugins.Phoenix do
  @moduledoc """
  `PromEx.Plugins.Phoenix` with HTTP metric labels the client can't choose.

  The upstream plugin tags its HTTP request, response size and request count
  metrics with the Host header and the method as the client sent them, so
  every scanner's made-up host, IP literal and method ("AHSN",
  "SSTP_DUPLEX_POST") creates series of its own. Those metrics drop the host
  label and label a method other than GET, HEAD, POST, PUT, PATCH, DELETE and
  OPTIONS as "OTHER".

  The upstream metrics are returned under their own names with their other
  labels and buckets, so the upstream Phoenix dashboard keeps working.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS)

  @impl true
  def event_metrics(opts) do
    opts
    |> PromEx.Plugins.Phoenix.event_metrics()
    |> Enum.map(&relabel/1)
  end

  defp relabel(%Event{group_name: :phoenix_http_event_metrics, metrics: metrics} = event) do
    %{event | metrics: Enum.map(metrics, &relabel_metric/1)}
  end

  defp relabel(event), do: event

  defp relabel_metric(%{tags: tags, tag_values: tag_values} = metric) do
    %{
      metric
      | tags: List.delete(tags, :host),
        tag_values: fn metadata -> metadata |> tag_values.() |> http_tags() end
    }
  end

  @doc false
  def http_tags(tags) do
    tags
    |> Map.delete(:host)
    |> Map.replace_lazy(:method, &method/1)
  end

  defp method(method) when method in @methods, do: method
  defp method(_method), do: "OTHER"
end
