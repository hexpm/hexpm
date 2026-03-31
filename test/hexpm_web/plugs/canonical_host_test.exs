defmodule HexpmWeb.Plugs.CanonicalHostTest do
  use HexpmWeb.ConnCase, async: false

  alias HexpmWeb.Plugs.CanonicalHost

  setup do
    original = Application.get_env(:hexpm, HexpmWeb.Endpoint)
    on_exit(fn -> Application.put_env(:hexpm, HexpmWeb.Endpoint, original) end)
  end

  defp put_canonical_host(host) do
    config = Application.get_env(:hexpm, HexpmWeb.Endpoint)
    Application.put_env(:hexpm, HexpmWeb.Endpoint, put_in(config[:url][:host], host))
  end

  describe "call/2" do
    test "redirects www host to canonical host" do
      put_canonical_host("hex.pm")

      conn =
        build_conn(:get, "/packages/ecto")
        |> Map.put(:host, "www.hex.pm")
        |> CanonicalHost.call([])

      assert conn.halted
      assert conn.status == 301
      [location] = get_resp_header(conn, "location")
      assert location == "https://hex.pm/packages/ecto"
    end

    test "preserves query string on redirect" do
      put_canonical_host("hex.pm")

      conn =
        build_conn(:get, "/packages?search=ecto&sort=recent_downloads")
        |> Map.put(:host, "www.hex.pm")
        |> CanonicalHost.call([])

      assert conn.halted
      assert conn.status == 301
      [location] = get_resp_header(conn, "location")
      assert location == "https://hex.pm/packages?search=ecto&sort=recent_downloads"
    end

    test "does not redirect when host matches canonical host" do
      put_canonical_host("hex.pm")

      conn =
        build_conn(:get, "/packages")
        |> Map.put(:host, "hex.pm")
        |> CanonicalHost.call([])

      refute conn.halted
    end

    test "does not redirect subdomains" do
      put_canonical_host("hex.pm")

      conn =
        build_conn(:get, "/ecto/1.0.0")
        |> Map.put(:host, "readme.hex.pm")
        |> CanonicalHost.call([])

      refute conn.halted
    end
  end
end
