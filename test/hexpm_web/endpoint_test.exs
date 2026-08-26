defmodule HexpmWeb.EndpointTest do
  use HexpmWeb.ConnCase, async: true

  test "emits the endpoint telemetry event PromEx builds its Phoenix metrics from" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:phoenix, :endpoint, :stop]])

    get(build_conn(), "/diffs")

    assert_received {[:phoenix, :endpoint, :stop], ^ref, %{duration: _}, %{conn: %Plug.Conn{}}}

    :telemetry.detach(ref)
  end

  test "ignores a client-supplied request id" do
    conn =
      build_conn()
      |> put_req_header("x-request-id", "client-chosen-id-000000001")
      |> get("/diffs")

    assert [request_id] = get_resp_header(conn, "x-request-id")
    assert request_id != "client-chosen-id-000000001"
    assert byte_size(request_id) >= 20
  end
end
