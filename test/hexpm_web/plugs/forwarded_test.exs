defmodule HexpmWeb.Plugs.ForwardedTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias HexpmWeb.Plugs.Forwarded

  @load_balancer {130, 211, 1, 7}

  test "uses the client address the load balancer appended" do
    assert Forwarded.remote_ip(@load_balancer, ["203.0.113.10, 198.51.100.1"]) ==
             {203, 0, 113, 10}

    assert Forwarded.remote_ip({35, 191, 200, 3}, ["203.0.113.10,198.51.100.1"]) ==
             {203, 0, 113, 10}
  end

  test "ignores addresses the client sent before the load balancer's entries" do
    assert Forwarded.remote_ip(@load_balancer, ["127.0.0.1, 203.0.113.10, 198.51.100.1"]) ==
             {203, 0, 113, 10}

    assert Forwarded.remote_ip(@load_balancer, ["127.0.0.1", "203.0.113.10, 198.51.100.1"]) ==
             {203, 0, 113, 10}
  end

  test "trusts load balancer peers reported as IPv4-mapped IPv6 addresses" do
    peer = {0, 0, 0, 0, 0, 0xFFFF, 0x82D3, 0x0107}

    assert Forwarded.remote_ip(peer, ["203.0.113.10, 198.51.100.1"]) == {203, 0, 113, 10}
  end

  test "ignores the header from peers outside the load balancer ranges" do
    for peer <- [
          {10, 128, 0, 5},
          {10, 36, 1, 2},
          {127, 0, 0, 1},
          {130, 211, 4, 1},
          {35, 192, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x0A80, 0x0005},
          {0, 0, 0, 0, 0, 0, 0, 1}
        ] do
      assert Forwarded.remote_ip(peer, ["127.0.0.1, 10.0.0.1"]) == peer
    end
  end

  test "keeps the load balancer address when the header is missing" do
    assert Forwarded.remote_ip(@load_balancer, []) == @load_balancer
    assert Forwarded.remote_ip(@load_balancer, ["203.0.113.10"]) == @load_balancer
  end

  test "keeps the load balancer address when the header is invalid" do
    log =
      capture_log(fn ->
        assert Forwarded.remote_ip(@load_balancer, ["invalid, 198.51.100.1"]) == @load_balancer
      end)

    assert log =~ "Invalid IP: \"invalid\""
  end

  test "sets remote_ip on the conn" do
    conn =
      conn(:get, "/")
      |> Map.put(:remote_ip, @load_balancer)
      |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.10, 198.51.100.1")
      |> Forwarded.call([])

    assert conn.remote_ip == {203, 0, 113, 10}

    conn =
      conn(:get, "/")
      |> Map.put(:remote_ip, {10, 128, 0, 5})
      |> Plug.Conn.put_req_header("x-forwarded-for", "127.0.0.1, 198.51.100.1")
      |> Forwarded.call([])

    assert conn.remote_ip == {10, 128, 0, 5}
  end
end
