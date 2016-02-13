defmodule HexWeb.RateLimitTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Hello do
    # need to use Phoenix.Controller because RateLimit.Plug uses ErrorView
    # which in turn requres `plug :accepts`
    use Phoenix.Controller

    plug :accepts, ~w(json)
    plug HexWeb.RateLimit.Plug

    def index(conn, _params) do
      send_resp(conn, 200, "Hello, World!")
    end
  end

  test "allows requests when limit is not exceeded" do
    conn = request({0, 0, 0, 0})
    assert conn.status == 200
    assert conn.resp_body == "Hello, World!"
    assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
    assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]
  end

  test "halts requests when limit is exceeded" do
    Enum.each(99..0, fn i ->
      conn = request({1, 1, 1, 1})
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["#{i}"]
    end)

    conn = request({1, 1, 1, 1})
    assert conn.status == 429
    assert conn.resp_body == Poison.encode!(%{status: 429, message: "API rate limit exceeded for 1.1.1.1"})
  end

  test "allows requests again when limit expired" do
    conn = request({2, 2, 2, 2})
    assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]

    send(HexWeb.RateLimit, {:prune_timer, 0})

    conn = request({2, 2, 2, 2})
    assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]
  end

  test "doesn't limit requests from 127.0.0.1" do
    conn = request({127, 0, 0, 1})
    assert conn.status == 200
    assert conn.resp_body == "Hello, World!"
    assert get_resp_header(conn, "x-ratelimit-limit") == []
  end

  defp request(remote_ip) do
    conn(:get, "/")
    |> Map.put(:remote_ip, remote_ip)
    |> Hello.call(:index)
  end
end
