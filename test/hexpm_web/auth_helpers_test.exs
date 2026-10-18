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

  test "counts every request carrying credentials by scheme and result", %{user: user} do
    ref = make_ref()

    :telemetry.attach(
      {__MODULE__, ref},
      [:hexpm, :api, :authenticate],
      &__MODULE__.forward_event/4,
      %{pid: self(), ref: ref}
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)

    now = ~U[2026-09-30 23:59:59Z]
    basic = "Basic " <> Base.encode64("#{user.username}:password")

    user |> auth_conn(basic) |> AuthHelpers.authenticate_at(now)
    assert_receive {^ref, %{count: 1}, %{scheme: :basic, result: :ok}}

    user |> auth_conn(basic) |> AuthHelpers.authenticate_at(~U[2026-10-01 00:00:00Z])
    assert_receive {^ref, %{count: 1}, %{scheme: :basic, result: :basic_auth_disabled}}

    user
    |> auth_conn("Basic " <> Base.encode64("#{user.username}:wrong"))
    |> AuthHelpers.authenticate_at(now)

    assert_receive {^ref, %{count: 1}, %{scheme: :basic, result: :password}}

    user |> auth_conn("Basic not-base64") |> AuthHelpers.authenticate_at(now)
    assert_receive {^ref, %{count: 1}, %{scheme: :basic, result: :invalid}}

    key = Key.build(user, %{name: "api-key"}) |> Repo.insert!()
    user |> auth_conn(key.user_secret) |> AuthHelpers.authenticate_at(now)
    assert_receive {^ref, %{count: 1}, %{scheme: :key, result: :ok}}

    user |> auth_conn("no-such-key") |> AuthHelpers.authenticate_at(now)
    assert_receive {^ref, %{count: 1}, %{scheme: :key, result: :key}}

    user |> auth_conn("Bearer no-such-token") |> AuthHelpers.authenticate_at(now)
    assert_receive {^ref, %{count: 1}, %{scheme: :bearer, result: :invalid_token}}

    user
    |> auth_conn("Bearer " <> Key.token_prefix() <> "no-such-key")
    |> AuthHelpers.authenticate_at(now)

    assert_receive {^ref, %{count: 1}, %{scheme: :bearer, result: :key}}

    assert {:error, :missing} = AuthHelpers.authenticate_at(build_conn(), now)
    refute_received {^ref, _, _}
  end

  # Only events the test process itself executes are forwarded, so key and
  # token authentication in concurrently running tests never reach the mailbox.
  def forward_event(_event, measurements, metadata, %{pid: pid, ref: ref}) do
    if self() == pid, do: send(pid, {ref, measurements, metadata})
  end

  test "records a wrong Basic password", %{user: user} do
    conn = auth_conn(user, "Basic " <> Base.encode64("#{user.username}:wrong"))

    assert {:error, :password} = AuthHelpers.authenticate_at(conn, ~U[2026-09-30 23:59:59Z])

    username = user.username

    assert_received {Hexpm.LogLines, :warning,
                     %{
                       method: "password",
                       reason: "wrong_password",
                       username: ^username,
                       user_agent: "TEST",
                       ip: "127.0.0.1"
                     }}
  end

  test "refuses Basic credentials Postgres can't store before looking up the user", %{
    user: user
  } do
    for credentials <- ["#{user.username}\0:password", <<"#{user.username}", 0xFF, ":password">>] do
      conn = auth_conn(user, "Basic " <> Base.encode64(credentials))

      assert {:error, :invalid} = AuthHelpers.authenticate_at(conn, ~U[2026-09-30 23:59:59Z])
    end
  end

  test "records an invalid Bearer token", %{user: user} do
    conn = auth_conn(user, "Bearer not-a-jwt")

    assert {:error, :invalid_token} = AuthHelpers.authenticate_at(conn, ~U[2026-09-30 23:59:59Z])
    assert_received {Hexpm.LogLines, :warning, %{method: "oauth_token", reason: "invalid"}}
  end

  describe "a refused Bearer access token" do
    test "gets the invalid_token challenge when it was revoked", %{user: user} do
      client = insert(:oauth_client)
      oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

      {:ok, token} =
        Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "invalid-token-challenge",
          user_session_id: oauth_session.id
        )

      {:ok, _token} = Tokens.revoke(token)

      assert_invalid_token_challenge("Bearer " <> token.access_token)
    end

    test "gets the invalid_token challenge when it expired", %{user: user} do
      {:ok, access_token, _jti} =
        Hexpm.OAuth.JWT.generate_access_token(user.username, "user", ["api"], expires_in: -60)

      assert_invalid_token_challenge("Bearer " <> access_token)
    end

    test "gets the invalid_token challenge when it doesn't verify" do
      assert_invalid_token_challenge("Bearer invalid.jwt.token")
    end

    test "gets the invalid_token challenge when it's an API key" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> Key.token_prefix() <> "no-such-key")
        |> get("/api/users/me")

      assert json_response(conn, 401)["message"] == "invalid API key"

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer realm="hex", error="invalid_token")
             ]
    end
  end

  test "an access token without the scope gets a 403 with the insufficient_scope challenge", %{
    user: user
  } do
    client = insert(:oauth_client)
    oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        ["repositories"],
        "authorization_code",
        "insufficient-scope",
        user_session_id: oauth_session.id
      )

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token.access_token)
      |> get("/api/users/me")

    assert json_response(conn, 403)["message"] == "insufficient scope for this action"

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer realm="hex", error="insufficient_scope")
           ]
  end

  test "an API key sent on its own without the permission keeps the 401", %{user: user} do
    conn =
      build_conn()
      |> put_req_header("authorization", key_for(user, [%{domain: "repositories"}]))
      |> get("/api/users/me")

    assert json_response(conn, 401)["message"] == "key not authorized for this action"
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="hex")]
  end

  test "a request without credentials gets the Bearer challenge with no error code" do
    conn = get(build_conn(), "/api/users/me")

    assert json_response(conn, 401)["message"] == "missing authentication information"
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="hex")]
  end

  test "a refused Basic password gets the Basic challenge with a quoted realm", %{user: user} do
    conn =
      user
      |> auth_conn("Basic " <> Base.encode64("#{user.username}:wrong"))
      |> AuthHelpers.error({:error, :password})

    assert json_response(conn, 401)["message"] == "invalid username and password combination"
    assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="hex")]
  end

  defp assert_invalid_token_challenge(authorization) do
    conn =
      build_conn()
      |> put_req_header("authorization", authorization)
      |> get("/api/users/me")

    assert json_response(conn, 401)["message"] == "invalid or expired access token"

    # hex_core matches this exact header value to renew the credential
    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer realm="hex", error="invalid_token")
           ]
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
