defmodule HexpmWeb.ReadOnlyModeTest do
  use HexpmWeb.ConnCase

  import ExUnit.CaptureLog

  alias Hexpm.Accounts.{Key, Keys}
  alias Hexpm.OAuth.{Client, Clients, JWT, ReadOnly, Token, Tokens}
  alias Hexpm.Repository.Assets
  alias Hexpm.UserSessions

  setup do
    on_exit(fn -> ReadOnly.configure!(false) end)
    :ok
  end

  test "GET /api/auth" do
    user = insert(:user)
    key = insert(:key, user: user)
    ReadOnly.configure!(true)

    build_conn()
    |> put_req_header("authorization", key.user_secret)
    |> get("/api/auth", domain: "api")
    |> response(204)
  end

  test "API writes return a retryable maintenance error" do
    body = %{name: "macbook"}
    user = insert(:user)
    key = insert(:key, user: user)
    ReadOnly.configure!(true)

    conn =
      build_conn()
      |> put_req_header("authorization", key.user_secret)
      |> post("/api/keys", body)

    assert %{
             "error" => "temporarily_unavailable",
             "message" => message,
             "status" => 503
           } = json_response(conn, 503)

    assert message =~ "temporarily read-only for maintenance"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "retry-after") == ["60"]
    assert conn.private.logster_log_level == :info
  end

  test "Hexpm.Repo.insert_all is gated by read-only mode" do
    ReadOnly.configure!(true)

    assert_raise Hexpm.WriteInReadOnlyMode, fn ->
      Hexpm.Repo.insert_all("security_advisory_affected_releases", [])
    end
  end

  test "browser writes return a maintenance page before CSRF validation" do
    ReadOnly.configure!(true)

    conn = post(build_conn(), "/signup", %{})

    assert response(conn, 503) =~ "temporarily read-only for maintenance"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "retry-after") == ["60"]
    assert get_resp_header(conn, "content-security-policy") != []
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert conn.private.logster_log_level == :info
  end

  test "expected write attempts do not produce error logs" do
    ReadOnly.configure!(true)

    log =
      capture_log(fn ->
        build_conn()
        |> post("/signup", %{})
        |> response(503)
      end)

    refute log =~ "[error]"
    refute log =~ "WriteInReadOnlyMode"
  end

  test "logout clears the local browser session without writing revocation state" do
    user = insert(:user)
    conn = test_login(build_conn(), user)
    [session] = UserSessions.all_for_user(user)
    ReadOnly.configure!(true)

    conn = post(conn, "/logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "session_token")
    assert Repo.get!(Hexpm.UserSession, session.id).revoked_at == nil
  end

  test "authenticated browser reads do not update session usage" do
    user = insert(:user)
    conn = test_login(build_conn(), user)
    [session] = UserSessions.all_for_user(user)
    assert session.last_use == nil

    ReadOnly.configure!(true)

    conn = get(conn, "/dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
    assert Repo.get!(Hexpm.UserSession, session.id).last_use == nil
  end

  test "upload writes are rejected before authentication and body handling" do
    ReadOnly.configure!(true)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/octet-stream")
      |> post("/api/publish", "not a package")

    assert json_response(conn, 503)["error"] == "temporarily_unavailable"
    assert conn.private.logster_log_level == :info
  end

  test "write errors use every supported API response format" do
    ReadOnly.configure!(true)

    for {content_type, decode} <- [
          {"application/vnd.hex+json", &Jason.decode!/1},
          {"application/vnd.hex+elixir",
           fn body ->
             {:ok, term} = HexpmWeb.ElixirFormat.decode(body)
             term
           end},
          {"application/vnd.hex+erlang", &:erlang.binary_to_term/1}
        ] do
      conn =
        build_conn()
        |> put_req_header("accept", content_type)
        |> post("/api/keys", %{name: "macbook"})

      response = conn |> response(503) |> decode.()
      assert response["error"] == "temporarily_unavailable"
      assert response["message"] =~ "temporarily read-only for maintenance"
      assert response["status"] == 503
    end
  end

  test "external billing mutations are blocked before calling the provider" do
    parent = self()
    stub(Hexpm.Billing.Mock, :update, fn _, _ -> send(parent, :billing_called) end)
    ReadOnly.configure!(true)

    assert_raise Hexpm.WriteInReadOnlyMode, fn ->
      Hexpm.Billing.update("organization", %{"quantity" => 2})
    end

    refute_received :billing_called
  end

  test "package asset mutations are blocked before storage changes" do
    release = insert(:release, package: insert(:package))
    ReadOnly.configure!(true)

    assert_raise Hexpm.WriteInReadOnlyMode, fn -> Assets.revert_release(release) end
  end

  test "client credentials issue a row-less machine token" do
    user = insert(:user)
    {:ok, %{key: key}} = Keys.create(user, %{name: "ci"}, audit: audit_data(user))
    client = oauth_client(["client_credentials"], ["api"])
    ReadOnly.configure!(true)

    conn =
      post(build_conn(), ~p"/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => client.client_id,
        "client_secret" => key.user_secret,
        "scope" => "api"
      })

    response = json_response(conn, 200)
    refute response["refresh_token"]
    assert {:ok, claims} = JWT.verify_and_decode(response["access_token"])
    assert claims["token_use"] == "machine"
    assert claims["key_id"] == key.id
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
    refute Repo.get_by(Token, jti: claims["jti"])
    assert Hexpm.UserSessions.all_for_user(user) == []
    assert Repo.get(Key, key.id).last_use == nil
  end

  test "read-only refresh is unavailable without changing the grant" do
    user = insert(:user)
    client = oauth_client(["refresh_token"], ["repositories"])

    {:ok, token} =
      Tokens.create_and_insert_for_user(
        user,
        client.client_id,
        ["repositories"],
        "authorization_code",
        nil,
        with_refresh_token: true
      )

    token_count = Repo.aggregate(Token, :count)
    ReadOnly.configure!(true)

    conn =
      post(build_conn(), ~p"/api/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => token.refresh_token,
        "client_id" => client.client_id
      })

    response = json_response(conn, 503)
    assert response["error"] == "temporarily_unavailable"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "retry-after") == ["60"]
    assert conn.private.logster_log_level == :info
    assert Repo.get!(Token, token.id).revoked_at == nil
    assert Repo.aggregate(Token, :count) == token_count
  end

  test "client credentials omit explicit repositories the user can no longer access" do
    user = insert(:user)
    organization = insert(:organization)
    membership = insert(:organization_user, user: user, organization: organization)

    {:ok, %{key: key}} =
      Keys.create(
        user,
        %{
          name: "former-org",
          permissions: [%{domain: "repository", resource: organization.name}]
        },
        audit: audit_data(user)
      )

    client = oauth_client(["client_credentials"], ["repositories"])
    Repo.delete!(membership)
    ReadOnly.configure!(true)

    conn =
      post(build_conn(), ~p"/api/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => client.client_id,
        "client_secret" => key.user_secret,
        "scope" => "repository:#{organization.name}"
      })

    assert json_response(conn, 400)["error"] == "invalid_scope"
  end

  test "write-dependent OAuth flows return a retryable error" do
    client =
      oauth_client(
        ["urn:ietf:params:oauth:grant-type:device_code"],
        ["api"]
      )

    ReadOnly.configure!(true)

    conn =
      post(build_conn(), ~p"/api/oauth/device_authorization", %{
        "client_id" => client.client_id,
        "scope" => "api"
      })

    assert json_response(conn, 503)["error"] == "temporarily_unavailable"
    assert get_resp_header(conn, "retry-after") == ["60"]
    assert conn.private.logster_log_level == :info
  end

  test "read-only write errors map to service unavailable" do
    assert Plug.Exception.status(%Hexpm.WriteInReadOnlyMode{}) == 503
  end

  defp oauth_client(grant_types, scopes) do
    params = %{
      client_id: Clients.generate_client_id(),
      name: "Read-only test client",
      client_type: "public",
      allowed_grant_types: grant_types,
      allowed_scopes: scopes
    }

    Client.build(params) |> Repo.insert!()
  end
end
