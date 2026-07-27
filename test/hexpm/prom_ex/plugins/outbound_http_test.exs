defmodule Hexpm.PromEx.Plugins.OutboundHttpTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.OutboundHttp

  defp request(host \\ "s3.amazonaws.com", method \\ "GET") do
    Finch.build(method, "https://#{host}/")
  end

  test "tags a response by host, method and status" do
    tags = OutboundHttp.request_tags(%{request: request(), result: {:ok, %{status: 200}}})

    assert tags == %{host: "s3.amazonaws.com", method: "GET", status: 200}
  end

  test "counts a failed request rather than dropping it" do
    result = {:error, %Mint.TransportError{reason: :timeout}}
    tags = OutboundHttp.request_tags(%{request: request(), result: result})

    assert tags.status == "Mint.TransportError"
  end

  test "falls back when the result is not a response" do
    assert OutboundHttp.request_tags(%{request: request(), result: nil}).status == "unknown"
  end

  test "attaches to the Finch events the requests actually emit" do
    events =
      [otp_app: :hexpm]
      |> OutboundHttp.event_metrics()
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.map(& &1.event_name)
      |> Enum.uniq()

    assert [:finch, :request, :stop] in events
    assert [:finch, :request, :exception] in events
    assert [:finch, :queue, :stop] in events
    assert [:finch, :connect, :stop] in events
  end
end
