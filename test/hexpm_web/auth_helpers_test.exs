defmodule HexpmWeb.AuthHelpersTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.Key
  alias Hexpm.OAuth.Tokens
  alias HexpmWeb.AuthHelpers

  setup do
    %{user: insert(:user)}
  end

  test "authenticates Basic credentials outside a brownout", %{user: user} do
    assert {:ok, %{user: authenticated_user}} =
             user
             |> auth_conn("Basic " <> Base.encode64("#{user.username}:password"))
             |> AuthHelpers.authenticate_at(~U[2026-09-30 23:59:59Z])

    assert authenticated_user.id == user.id
  end

  test "rejects Basic credentials during brownouts and after the cutoff", %{user: user} do
    conn = auth_conn(user, "Basic " <> Base.encode64("#{user.username}:password"))

    assert {:error, :basic_auth_disabled} =
             AuthHelpers.authenticate_at(conn, ~U[2026-10-01 00:00:00Z])

    assert {:error, :basic_auth_disabled} =
             AuthHelpers.authenticate_at(conn, ~U[2026-11-01 00:00:00Z])

    conn = AuthHelpers.error(conn, {:error, :basic_auth_disabled})

    assert json_response(conn, 401)["message"] ==
             "Basic authentication is disabled. Update your client to use OAuth or an API key."

    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="hex")]
  end

  test "does not affect API key or OAuth authentication during a brownout", %{user: user} do
    key = Key.build(user, %{name: "api-key"}) |> Repo.insert!()

    assert {:ok, %{user: key_user}} =
             user
             |> auth_conn(key.user_secret)
             |> AuthHelpers.authenticate_at(~U[2026-10-31 13:00:00Z])

    client = insert(:oauth_client)
    oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        ["api"],
        "authorization_code",
        "basic-auth-brownout",
        user_session_id: oauth_session.id
      )

    assert {:ok, %{user: oauth_user}} =
             user
             |> auth_conn("Bearer " <> token.access_token)
             |> AuthHelpers.authenticate_at(~U[2026-10-31 13:00:00Z])

    assert key_user.id == user.id
    assert oauth_user.id == user.id
  end

  defp auth_conn(user, authorization) do
    build_conn()
    |> fetch_query_params()
    |> put_private(:phoenix_format, "json")
    |> Map.put(:remote_ip, {127, 0, 0, 1})
    |> put_req_header("authorization", authorization)
    |> put_req_header("user-agent", "TEST")
    |> assign(:current_user, user)
  end
end
