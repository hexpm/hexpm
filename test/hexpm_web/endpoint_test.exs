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

  test "marks the session cookie Secure" do
    conn = get(build_conn(), "/password/new?username=eric&key=key")

    assert [cookie] =
             conn
             |> get_resp_header("set-cookie")
             |> Enum.filter(&String.starts_with?(&1, "_hexpm_key="))

    assert "secure" in String.split(cookie, "; ")
  end

  describe "plain HTTP forwarded by the load balancer" do
    test "redirects static files before Plug.Static serves them" do
      for path <- ["/robots.txt", "/favicon.ico", "/images/dashbit.png"] do
        conn = get(forwarded("https"), path)
        assert conn.status == 200
        assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]

        assert redirected_to(get(forwarded("http"), path), 301) == "https://hex.pm#{path}"
      end
    end

    test "redirects a LiveView socket upgrade instead of upgrading it" do
      assert websocket_upgrade(forwarded("https")).state == :upgraded

      assert redirected_to(websocket_upgrade(forwarded("http")), 301) ==
               "https://hex.pm/live/websocket?vsn=2.0.0"
    end

    test "redirects GET and HEAD with 301" do
      assert redirected_to(get(forwarded("http"), "/packages?search=ecto"), 301) ==
               "https://hex.pm/packages?search=ecto"

      assert redirected_to(head(forwarded("http"), "/packages"), 301) ==
               "https://hex.pm/packages"
    end

    test "redirects other methods with 307 so clients repeat the method" do
      assert redirected_to(post(forwarded("http"), "/api/publish"), 307) ==
               "https://hex.pm/api/publish"

      assert redirected_to(delete(forwarded("http"), "/api/packages/ecto/owners/eric"), 307) ==
               "https://hex.pm/api/packages/ecto/owners/eric"
    end

    test "redirects to the requested host" do
      assert redirected_to(get(forwarded("http", "readme.hex.pm"), "/ecto/1.0.0"), 301) ==
               "https://readme.hex.pm/ecto/1.0.0"
    end

    test "answers the readiness probe" do
      assert response(get(forwarded("http", "10.0.0.1"), "/status"), 200)
    end
  end

  defp forwarded(proto, host \\ "hex.pm") do
    put_req_header(%{build_conn() | host: host}, "x-forwarded-proto", proto)
  end

  # put_req_header/3 refuses "host", which the upgrade validation requires
  defp websocket_upgrade(conn) do
    %{conn | req_headers: [{"host", conn.host} | conn.req_headers]}
    |> put_req_header("connection", "Upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
    |> put_req_header("sec-websocket-version", "13")
    |> get("/live/websocket?vsn=2.0.0")
  end
end
