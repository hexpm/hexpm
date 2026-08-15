defmodule HexpmWeb.Plugs.ForwardedTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Plugs.Forwarded

  test "extracts the client address from load balancer forwarding headers" do
    assert Forwarded.remote_ip({127, 0, 0, 1}, ["203.0.113.10, 10.0.0.1, 10.0.0.2"]) ==
             {10, 0, 0, 1}
  end

  test "falls back to the peer address for missing or invalid forwarding headers" do
    peer = {127, 0, 0, 1}
    assert Forwarded.remote_ip(peer, []) == peer
    assert Forwarded.remote_ip(peer, ["invalid, proxy"]) == peer
  end
end
