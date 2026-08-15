defmodule Hexpm.PromEx.Plugins.OutboundHttp do
  @moduledoc """
  PromEx plugin for the HTTP calls this application makes.

  Everything outbound goes through Finch, whether it is reached directly, through
  Req, through Tesla or through ExAws, so instrumenting Finch covers all of them
  without each library needing its own plugin.

  Requests are tagged by host rather than by full URL, which keeps the number of
  series bounded by the handful of services we talk to.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :outbound_http))

    Event.build(:hexpm_outbound_http_event_metrics, [
      distribution(
        metric_prefix ++ [:request, :duration, :milliseconds],
        event_name: [:finch, :request, :stop],
        measurement: :duration,
        description: "How long an outbound HTTP request took.",
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000]],
        tags: [:host, :method, :status],
        tag_values: &__MODULE__.request_tags/1,
        unit: {:native, :millisecond}
      ),
      counter(
        metric_prefix ++ [:request, :total],
        event_name: [:finch, :request, :stop],
        description: "Outbound HTTP requests that produced a response or an error.",
        tags: [:host, :method, :status],
        tag_values: &__MODULE__.request_tags/1
      ),
      counter(
        metric_prefix ++ [:request, :exception, :total],
        event_name: [:finch, :request, :exception],
        description: "Outbound HTTP requests that raised.",
        tags: [:host, :method, :kind],
        tag_values: &__MODULE__.exception_tags/1
      ),
      distribution(
        metric_prefix ++ [:queue, :duration, :milliseconds],
        event_name: [:finch, :queue, :stop],
        measurement: :duration,
        description:
          "How long a request waited for a connection from the pool. Sustained time here means the pool is too small.",
        reporter_options: [buckets: [1, 5, 10, 50, 100, 250, 500, 1_000, 5_000]],
        tags: [:host],
        tag_values: &__MODULE__.pool_tags/1,
        unit: {:native, :millisecond}
      ),
      distribution(
        metric_prefix ++ [:connect, :duration, :milliseconds],
        event_name: [:finch, :connect, :stop],
        measurement: :duration,
        description: "How long establishing a new connection took.",
        reporter_options: [buckets: [1, 5, 10, 50, 100, 250, 500, 1_000, 5_000]],
        tags: [:host],
        tag_values: &__MODULE__.pool_tags/1,
        unit: {:native, :millisecond}
      )
    ])
  end

  @doc false
  def request_tags(%{request: request} = metadata) do
    %{
      host: request.host,
      method: request.method,
      status: status(Map.get(metadata, :result))
    }
  end

  @doc false
  def exception_tags(%{request: request} = metadata) do
    %{
      host: request.host,
      method: request.method,
      kind: Map.get(metadata, :kind, :error)
    }
  end

  @doc false
  def pool_tags(metadata) do
    %{host: Map.get(metadata, :host, "unknown")}
  end

  # A request that never got a response is still worth counting, so failures are
  # labelled rather than dropped.
  defp status({:ok, %{status: status}}), do: status
  defp status({:ok, _other}), do: "ok"
  defp status({:error, %{__struct__: module}}), do: inspect(module)
  defp status({:error, _other}), do: "error"
  defp status(_), do: "unknown"
end
