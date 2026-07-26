defmodule HexpmWeb.EndpointTest do
  use HexpmWeb.ConnCase, async: true

  test "emits the endpoint telemetry event PromEx builds its Phoenix metrics from" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:phoenix, :endpoint, :stop]])

    get(build_conn(), "/diffs")

    assert_received {[:phoenix, :endpoint, :stop], ^ref, %{duration: _}, %{conn: %Plug.Conn{}}}

    :telemetry.detach(ref)
  end
end
