defmodule HexpmWeb.ReadOnlyModeTest do
  use HexpmWeb.ConnCase

  test "GET /api/auth" do
    user = insert(:user)
    key = insert(:key, user: user)

    Application.put_env(:hexpm, :read_only_mode, true)

    build_conn()
    |> put_req_header("authorization", key.user_secret)
    |> get("api/auth", domain: "api")
    |> response(204)
  after
    Application.put_env(:hexpm, :read_only_mode, false)
  end

  test "POST /api/keys" do
    body = %{name: "macbook"}
    user = insert(:user)
    key = insert(:key, user: user)

    Application.put_env(:hexpm, :read_only_mode, true)

    assert_raise Hexpm.WriteInReadOnlyMode, fn ->
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> post("api/keys", body)
    end
  after
    Application.put_env(:hexpm, :read_only_mode, false)
  end
end
