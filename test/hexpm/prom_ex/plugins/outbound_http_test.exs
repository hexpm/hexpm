defmodule Hexpm.PromEx.Plugins.OutboundHttpTest do
  use ExUnit.Case, async: true

  import Hexpm.TestHelpers, only: [capture_final_requests: 1, start_bandit: 1]

  alias Hexpm.PromEx.Plugins.OutboundHttp

  defmodule Server do
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, _opts), do: Plug.Conn.send_resp(conn, 200, "ok")
  end

  @finch_events [
    [:finch, :request, :stop],
    [:finch, :request, :exception],
    [:finch, :queue, :stop],
    [:finch, :connect, :stop]
  ]

  # Each package's docs are fetched from its own subdomain, and the rest are
  # hosts the alerts and dashboards select by name.
  @hosts [
    {"ecto.hexdocs.pm", "*.hexdocs.pm"},
    {"ecto.staging.hexdocs.pm", "*.hexdocs.pm"},
    {"hexdocs.pm", "hexdocs.pm"},
    {"api.sendgrid.com", "api.sendgrid.com"},
    {"api.github.com", "api.github.com"},
    {"storage.googleapis.com", "storage.googleapis.com"}
  ]

  defp request(host \\ "s3.amazonaws.com", method \\ "GET") do
    Finch.build(method, "https://#{host}/")
  end

  defp metrics() do
    [otp_app: :hexpm]
    |> OutboundHttp.event_metrics()
    |> List.wrap()
    |> Enum.flat_map(& &1.metrics)
  end

  # The labels each metric on `event` exports for `metadata`.
  defp labels(event, metadata) do
    for metric <- metrics(), metric.event_name == event, uniq: true do
      metadata |> metric.tag_values.() |> Map.take(metric.tags)
    end
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

  test "tags a final outcome by host the way it tags each attempt" do
    for {host, label} <- @hosts do
      [metadata] =
        capture_final_requests(fn ->
          Hexpm.HTTP.track_request(:head, "https://#{host}/ecto", fn -> {:ok, 200, [], ""} end)
        end)

      assert labels([:hexpm, :http, :request, :stop], metadata) == [
               %{host: label, method: "HEAD", status: 200}
             ]
    end
  end

  test "attaches to attempt and final outcome events" do
    events = metrics() |> Enum.map(& &1.event_name) |> Enum.uniq()

    assert [:hexpm, :http, :request, :stop] in events

    for event <- @finch_events do
      assert event in events
    end
  end

  describe "with the events Finch emits" do
    setup do
      port = start_bandit(Server)
      start_supervised!({Finch, name: __MODULE__.Finch})

      ref = :telemetry_test.attach_event_handlers(self(), @finch_events)
      on_exit(fn -> :telemetry.detach(ref) end)

      %{url: "http://localhost:#{port}/", ref: ref}
    end

    test "tags a response, its wait for the pool and its connection by host", %{
      url: url,
      ref: ref
    } do
      assert {:ok, %Finch.Response{status: 200}} =
               :get |> Finch.build(url) |> Finch.request(__MODULE__.Finch)

      assert_receive {[:finch, :request, :stop], ^ref, _, %{name: __MODULE__.Finch} = request}
      assert_receive {[:finch, :queue, :stop], ^ref, _, %{name: __MODULE__.Finch} = queue}
      assert_receive {[:finch, :connect, :stop], ^ref, _, %{name: __MODULE__.Finch} = connect}

      assert labels([:finch, :request, :stop], request) == [
               %{host: "localhost", method: "GET", status: 200}
             ]

      assert labels([:finch, :queue, :stop], queue) == [%{host: "localhost"}]
      assert labels([:finch, :connect, :stop], connect) == [%{host: "localhost"}]

      for {host, label} <- @hosts do
        assert labels([:finch, :request, :stop], put_in(request.request.host, host)) == [
                 %{host: label, method: "GET", status: 200}
               ]

        assert labels([:finch, :queue, :stop], put_in(queue.request.host, host)) == [
                 %{host: label}
               ]

        assert labels([:finch, :connect, :stop], %{connect | host: host}) == [%{host: label}]
      end
    end

    test "tags a request that raised by host, method and kind", %{url: url, ref: ref} do
      assert_raise RuntimeError, "stream callback", fn ->
        :get
        |> Finch.build(url)
        |> Finch.stream(__MODULE__.Finch, nil, fn _entry, _acc -> raise "stream callback" end)
      end

      assert_receive {[:finch, :request, :exception], ^ref, _,
                      %{name: __MODULE__.Finch} = exception}

      assert labels([:finch, :request, :exception], exception) == [
               %{host: "localhost", method: "GET", kind: :error}
             ]

      for {host, label} <- @hosts do
        assert labels([:finch, :request, :exception], put_in(exception.request.host, host)) == [
                 %{host: label, method: "GET", kind: :error}
               ]
      end
    end
  end
end
