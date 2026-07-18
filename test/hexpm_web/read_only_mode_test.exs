defmodule HexpmWeb.ReadOnlyModeTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.{Key, Keys}
  alias Hexpm.OAuth.{Client, Clients, JWT, ReadOnly, Token, Tokens}

  setup do
    on_exit(fn -> ReadOnly.configure!(false) end)
    :ok
  end

  test "GET /api/auth" do
    user = insert(:user)
    key = insert(:key, user: user)

    Application.put_env(:hexpm, :read_only_mode, true)

    build_conn()
    |> put_req_header("authorization", key.user_secret)
    |> get("/api/auth", domain: "api")
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
      |> post("/api/keys", body)
    end
  after
    Application.put_env(:hexpm, :read_only_mode, false)
  end

  test "Hexpm.Repo.insert_all is gated by read-only mode" do
    Application.put_env(:hexpm, :read_only_mode, true)

    assert_raise Hexpm.WriteInReadOnlyMode, fn ->
      Hexpm.Repo.insert_all("security_advisory_affected_releases", [])
    end
  after
    Application.put_env(:hexpm, :read_only_mode, false)
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
