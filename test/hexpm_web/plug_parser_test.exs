defmodule HexpmWeb.PlugParserTest do
  use HexpmWeb.ConnCase, async: true

  describe "erlang media request" do
    test "POST /api/keys" do
      user = insert(:user_with_tfa)
      erlang_params = HexpmWeb.ErlangFormat.encode_to_iodata!(%{name: "macbook"})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/vnd.hex+erlang")
        |> test_oauth_login(user)
        |> post("/api/keys", erlang_params)

      assert json_response(conn, 201)["name"] == "macbook"
    end
  end
end
