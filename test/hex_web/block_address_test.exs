defmodule HexWeb.BlockAddressTest do
  use ExUnit.Case, async: false
  use Plug.Test

  defmodule Hello do
    use Phoenix.Controller

    plug :accepts, ~w(json)
    plug HexWeb.BlockAddress.Plug

    def index(conn, _params) do
      send_resp(conn, 200, "Hello, World!")
    end
  end

  test "allows requests from IPs that are not blocked" do
    conn = request({0, 0, 0, 0})
    assert conn.status == 200
    assert conn.resp_body == "Hello, World!"
  end

  test "halts requests from IPs that are blocked" do
    HexWeb.Repo.insert!(%HexWeb.BlockedAddress{ip: "1.1.1.1", comment: "blocked"})
    HexWeb.BlockAddress.reload

    conn = request({1, 1, 1, 1})
    assert conn.status == 403
    assert conn.resp_body == Poison.encode!(%{status: 403, message: "Blocked"})
  end

  test "allows requests again when the IP is unblocked" do
    blocked_address = HexWeb.Repo.insert!(%HexWeb.BlockedAddress{ip: "2.2.2.2", comment: "blocked"})
    HexWeb.BlockAddress.reload

    conn = request({2, 2, 2, 2})
    assert conn.status == 403
    assert conn.resp_body == Poison.encode!(%{status: 403, message: "Blocked"})

    {:ok, _} = HexWeb.Repo.delete(blocked_address)
    HexWeb.BlockAddress.reload

    conn = request({2, 2, 2, 2})
    assert conn.status == 200
    assert conn.resp_body == "Hello, World!"
  end

  defp request(remote_ip) do
    conn(:get, "/")
    |> Map.put(:remote_ip, remote_ip)
    |> Hello.call(:index)
  end
end
