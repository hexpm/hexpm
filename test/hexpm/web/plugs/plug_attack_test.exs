defmodule Hexpm.Web.Plugs.AttackTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Hello do
    # need to use Phoenix.Controller because RateLimit.Plug uses ErrorView
    # which in turn requres `plug :accepts`
    use Phoenix.Controller

    plug :accepts, ~w(json)
    plug Hexpm.Web.Plugs.Attack

    def index(conn, _params) do
      send_resp(conn, 200, "Hello, World!")
    end
  end

  setup do
    PlugAttack.Storage.Ets.clean(Hexpm.Web.Plugs.Attack)
    :ok
  end

  describe "throttle" do

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

      PlugAttack.Storage.Ets.clean(Hexpm.Web.Plugs.Attack)

      conn = request({2, 2, 2, 2})
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]
    end

    test "doesn't limit requests from 127.0.0.1" do
      conn = request({127, 0, 0, 1})
      assert conn.status == 200
      assert conn.resp_body == "Hello, World!"
      assert get_resp_header(conn, "x-ratelimit-limit") == []
    end
  end

  describe "block addresses" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.Repo)
    end

    test "allows requests from IPs that are not blocked" do
      conn = request({0, 0, 0, 0})
      assert conn.status == 200
      assert conn.resp_body == "Hello, World!"
    end

    test "halts requests from IPs that are blocked" do
      Hexpm.Repo.insert!(%Hexpm.BlockAddress.Entry{ip: "10.1.1.1", comment: "blocked"})
      Hexpm.BlockAddress.reload

      conn = request({10, 1, 1, 1})
      assert conn.status == 403
      assert conn.resp_body == Poison.encode!(%{status: 403, message: "Blocked"})
    end

    test "allows requests again when the IP is unblocked" do
      blocked_address = Hexpm.Repo.insert!(%Hexpm.BlockAddress.Entry{ip: "20.2.2.2", comment: "blocked"})
      Hexpm.BlockAddress.reload

      conn = request({20, 2, 2, 2})
      assert conn.status == 403
      assert conn.resp_body == Poison.encode!(%{status: 403, message: "Blocked"})

      Hexpm.Repo.delete!(blocked_address)
      Hexpm.BlockAddress.reload

      conn = request({20, 2, 2, 2})
      assert conn.status == 200
      assert conn.resp_body == "Hello, World!"
    end
  end

  defp request(remote_ip) do
    conn(:get, "/")
    |> Map.put(:remote_ip, remote_ip)
    |> Hello.call(:index)
  end
end
