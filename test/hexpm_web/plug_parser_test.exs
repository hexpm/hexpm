defmodule HexpmWeb.PlugParserTest do
  use HexpmWeb.ConnCase

  describe "erlang media request" do
    test "POST /api/users" do
      params = %{
        username: Fake.sequence(:username),
        email: Fake.sequence(:email),
        password: "passpass"
      }

      erlang_params = HexpmWeb.ErlangFormat.encode_to_iodata!(params)

      build_conn()
      |> put_req_header("content-type", "application/vnd.hex+erlang")
      |> post("api/users", erlang_params)
      |> json_response(201)

      assert Hexpm.Repo.get_by!(Hexpm.Accounts.User, username: params.username)
    end
  end
end
