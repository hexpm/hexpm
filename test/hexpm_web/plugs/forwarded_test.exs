defmodule HexpmWeb.Plugs.ForwardedTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias HexpmWeb.Plugs.Forwarded

  @secret "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  @peer {10, 36, 1, 2}

  defp request(headers) do
    %{conn(:get, "/") | remote_ip: @peer, req_headers: headers}
  end

  test "uses the client address the load balancer appended" do
    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "203.0.113.10, 198.51.100.1"}
      ])

    assert Forwarded.remote_ip(conn, @secret) == {203, 0, 113, 10}
  end

  test "ignores addresses the client sent before the load balancer's entries" do
    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "127.0.0.1, 203.0.113.10, 198.51.100.1"}
      ])

    assert Forwarded.remote_ip(conn, @secret) == {203, 0, 113, 10}

    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "127.0.0.1"},
        {"x-forwarded-for", "203.0.113.10, 198.51.100.1"}
      ])

    assert Forwarded.remote_ip(conn, @secret) == {203, 0, 113, 10}
  end

  test "ignores the forwarding header without the load balancer secret" do
    conn = request([{"x-forwarded-for", "127.0.0.1, 198.51.100.1"}])
    assert Forwarded.remote_ip(conn, @secret) == @peer
  end

  test "ignores the forwarding header with a wrong load balancer secret" do
    for value <- ["", "wrong", String.upcase(@secret), @secret <> "0"] do
      conn =
        request([
          {"x-hexpm-load-balancer-secret", value},
          {"x-forwarded-for", "127.0.0.1, 198.51.100.1"}
        ])

      assert Forwarded.remote_ip(conn, @secret) == @peer
    end

    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "127.0.0.1, 198.51.100.1"}
      ])

    assert Forwarded.remote_ip(conn, @secret) == @peer
  end

  test "ignores the forwarding header when no secret is configured" do
    for secret <- [nil, ""] do
      conn =
        request([
          {"x-hexpm-load-balancer-secret", ""},
          {"x-forwarded-for", "127.0.0.1, 198.51.100.1"}
        ])

      assert Forwarded.remote_ip(conn, secret) == @peer
    end
  end

  test "keeps the peer address when the load balancer sends no client address" do
    conn = request([{"x-hexpm-load-balancer-secret", @secret}])
    assert Forwarded.remote_ip(conn, @secret) == @peer

    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "203.0.113.10"}
      ])

    assert Forwarded.remote_ip(conn, @secret) == @peer
  end

  test "keeps the peer address when the client address is invalid" do
    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "invalid, 198.51.100.1"}
      ])

    log = capture_log(fn -> assert Forwarded.remote_ip(conn, @secret) == @peer end)
    assert log =~ "Invalid IP: \"invalid\""
  end

  test "call/2 removes the secret header and ignores the forwarding header in test" do
    conn =
      request([
        {"x-hexpm-load-balancer-secret", @secret},
        {"x-forwarded-for", "127.0.0.1, 198.51.100.1"}
      ])
      |> Forwarded.call([])

    assert conn.remote_ip == @peer
    assert get_req_header(conn, "x-hexpm-load-balancer-secret") == []
  end
end
