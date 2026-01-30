defmodule HexpmWeb.API.OAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.{Repo}
  alias Hexpm.OAuth.{DeviceCodes, Client, Clients, Token, Tokens}

  setup do
    # Create test OAuth client
    client_params = %{
      client_id: Clients.generate_client_id(),
      name: "Test OAuth Client",
      client_type: "public",
      allowed_grant_types: ["urn:ietf:params:oauth:grant-type:device_code", "refresh_token"],
      allowed_scopes: ["api", "api:read", "api:write"]
    }

    {:ok, client} =
      Client.build(client_params)
      |> Repo.insert()

    %{client: client}
  end

  describe "POST /api/oauth/device_authorization" do
    test "initiates device authorization with valid client_id", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "api"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["device_code"]
      assert response["user_code"]
      assert response["verification_uri"]
      assert response["verification_uri_complete"]
      assert response["expires_in"] == 600
      assert response["interval"] == 5
    end

    test "handles multiple scopes", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "api:read api:write"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      # Verify device code was created with correct scopes
      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response["device_code"])
      assert device_code.scopes == ["api:read", "api:write"]
    end

    test "returns error for missing client_id" do
      conn = post(build_conn(), ~p"/api/oauth/device_authorization", %{})

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
    end

    test "returns error for invalid client_id" do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
    end

    test "returns error for unsupported scope", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "invalid_scope"
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_scope"
    end

    test "initiates device authorization with name parameter", %{client: client} do
      name = "TestMachine"

      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "api",
          "name" => name
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      # Verify device code was created with the name
      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response["device_code"])
      assert device_code.name == name
    end

    test "returns error for scope as array (malformed JSON)", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => ["api:write"]
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_scope"
    end

    test "returns error for client_id as array (malformed JSON)" do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => ["invalid"],
          "scope" => "api"
        })

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
    end

    test "handles name as non-string gracefully", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "api",
          "name" => ["invalid", "name"]
        })

      # Should succeed but ignore the malformed name
      assert json_response(conn, 200)
      response = json_response(conn, 200)

      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response["device_code"])
      assert device_code.name == nil
    end
  end

  describe "POST /api/oauth/token with device_code grant" do
    setup %{client: client} do
      conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} = DeviceCodes.initiate_device_authorization(conn, client.client_id, ["api"])
      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response.device_code)
      %{device_code: device_code, response: response}
    end

    test "returns authorization_pending for pending device code", %{
      client: client,
      response: response
    } do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => response.device_code,
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response_body = json_response(conn, 400)
      assert response_body["error"] == "authorization_pending"
    end

    test "returns access token for authorized device code", %{
      client: client,
      device_code: device_code
    } do
      # Authorize the device first
      user = insert(:user)
      {:ok, _} = DeviceCodes.authorize_device(device_code.user_code, user, device_code.scopes)

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => device_code.device_code,
          "client_id" => client.client_id
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["token_type"] == "bearer"
      assert response["expires_in"] > 0
      assert response["scope"] == "api"
    end

    test "returns error for invalid grant type", %{client: client, response: response} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "invalid",
          "device_code" => response.device_code,
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response_body = json_response(conn, 400)
      assert response_body["error"] == "unsupported_grant_type"
    end

    test "returns error for missing device_code", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response_body = json_response(conn, 400)
      assert response_body["error"] == "invalid_grant"
    end

    test "returns error for invalid device_code", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => "invalid_code",
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response_body = json_response(conn, 400)
      assert response_body["error"] == "invalid_grant"
    end

    test "returns error for mismatched client_id", %{response: response} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => response.device_code,
          "client_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 401)
      response_body = json_response(conn, 401)
      assert response_body["error"] == "invalid_client"
    end
  end

  describe "POST /api/oauth/token with refresh_token grant" do
    setup %{client: client} do
      user = insert(:user)

      conn =
        build_conn()
        |> Map.put(:scheme, :https)
        |> Map.put(:host, "hex.pm")
        |> Map.put(:port, 443)

      {:ok, response} = DeviceCodes.initiate_device_authorization(conn, client.client_id, ["api"])
      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response.device_code)

      # Authorize the device to get a token with refresh token
      {:ok, _} = DeviceCodes.authorize_device(device_code.user_code, user, device_code.scopes)

      # Get the token
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
          "device_code" => device_code.device_code,
          "client_id" => client.client_id
        })

      token_response = json_response(conn, 200)

      %{
        user: user,
        access_token: token_response["access_token"],
        refresh_token: token_response["refresh_token"]
      }
    end

    test "returns new access token for valid refresh token", %{
      client: client,
      refresh_token: refresh_token
    } do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id" => client.client_id
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["refresh_token"]
      assert response["token_type"] == "bearer"
      assert response["expires_in"] > 0
      assert response["scope"] == "api"

      # New tokens should be different
      refute response["access_token"] == refresh_token
      refute response["refresh_token"] == refresh_token
    end

    test "returns error for missing refresh_token", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_grant"
      assert response["error_description"] == "Missing refresh token"
    end

    test "returns error for invalid refresh_token", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => "invalid_token",
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_grant"
      assert response["error_description"] == "Invalid refresh token"
    end

    test "returns error for mismatched client_id", %{refresh_token: refresh_token} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
    end

    test "old refresh token becomes invalid after use", %{
      client: client,
      refresh_token: refresh_token
    } do
      # Use the refresh token
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id" => client.client_id
        })

      assert json_response(conn, 200)

      # Try to use the old refresh token again
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id" => client.client_id
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_grant"
      assert response["error_description"] == "Refresh token has been revoked"
    end

    test "returns error for expired refresh token", %{user: user, client: client} do
      {:ok, session} =
        Hexpm.UserSessions.create_oauth_session(user, client.client_id, audit: audit_data(user))

      # Create a token with an expired refresh token
      token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          user_session_id: session.id,
          with_refresh_token: true,
          audit: audit_data(user)
        )

      {:ok, token} = Hexpm.Repo.insert(token_changeset)

      # Manually expire the refresh token
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        token
        |> Ecto.Changeset.change(refresh_token_expires_at: past_time)
        |> Hexpm.Repo.update()

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => token.refresh_token,
          "client_id" => client.client_id
        })

      assert response = json_response(conn, 400)
      assert response["error"] == "invalid_grant"
      assert response["error_description"] == "Refresh token has expired"
    end
  end

  describe "POST /api/oauth/revoke" do
    setup do
      user = insert(:user)

      client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Test OAuth Client",
        client_type: "public",
        allowed_grant_types: ["authorization_code"],
        allowed_scopes: ["api", "api:read", "api:write", "repositories"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      {:ok, session} =
        Hexpm.UserSessions.create_oauth_session(user, client.client_id, audit: audit_data(user))

      # Create token with refresh token
      token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          "test_code",
          user_session_id: session.id,
          with_refresh_token: true,
          audit: audit_data(user)
        )

      {:ok, token} = Repo.insert(token_changeset)
      token = Repo.preload(token, :user)

      %{
        revoke_user: user,
        revoke_client: client,
        revoke_token: token,
        revoke_access_token: token.access_token,
        revoke_refresh_token: token.refresh_token
      }
    end

    test "successfully revokes access token", %{
      revoke_client: client,
      revoke_token: token,
      revoke_access_token: access_token
    } do
      params = %{
        token: access_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      updated_token = Repo.get(Token, token.id)
      assert Tokens.revoked?(updated_token)
    end

    test "successfully revokes refresh token", %{
      revoke_client: client,
      revoke_token: token,
      revoke_refresh_token: refresh_token
    } do
      params = %{
        token: refresh_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      updated_token = Repo.get(Token, token.id)
      assert Tokens.revoked?(updated_token)
    end

    test "returns 200 OK for invalid token (security per RFC 7009)", %{
      revoke_client: client
    } do
      params = %{
        token: "invalid_token_value",
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for invalid client_id (security per RFC 7009)", %{
      revoke_token: token,
      revoke_access_token: access_token
    } do
      params = %{
        token: access_token,
        client_id: Ecto.UUID.generate()
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      updated_token = Repo.get(Token, token.id)
      refute Tokens.revoked?(updated_token)
    end

    test "returns 200 OK for missing parameters" do
      params = %{}

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for missing token parameter", %{revoke_client: client} do
      params = %{client_id: client.client_id}

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for missing client_id parameter", %{
      revoke_access_token: access_token
    } do
      params = %{token: access_token}

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "handles revocation of already revoked token", %{
      revoke_client: client,
      revoke_token: token,
      revoke_access_token: access_token
    } do
      {:ok, _} = Tokens.revoke(token)

      params = %{
        token: access_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "handles token from different client", %{
      revoke_token: token,
      revoke_access_token: access_token
    } do
      other_client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Other OAuth Client",
        client_type: "public",
        allowed_grant_types: ["authorization_code"],
        allowed_scopes: ["api:read"]
      }

      {:ok, other_client} = Client.build(other_client_params) |> Repo.insert()

      params = %{
        token: access_token,
        client_id: other_client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      updated_token = Repo.get(Token, token.id)
      refute Tokens.revoked?(updated_token)
    end

    test "supports token_type_hint parameter (optional per RFC 7009)", %{
      revoke_client: client,
      revoke_token: token,
      revoke_access_token: access_token
    } do
      params = %{
        token: access_token,
        client_id: client.client_id,
        token_type_hint: "access_token"
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      updated_token = Repo.get(Token, token.id)
      assert Tokens.revoked?(updated_token)
    end
  end

  describe "POST /api/oauth/token with client_credentials grant" do
    setup do
      user = insert(:user)

      # Create API key for the user
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(user, %{name: "test-key"}, audit: audit_data(user))

      client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Test OAuth Client",
        client_type: "public",
        allowed_grant_types: ["client_credentials"],
        allowed_scopes: ["api", "repositories"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      %{
        user: user,
        api_key: key.user_secret,
        client: client
      }
    end

    test "returns access token for valid API key", %{
      client: client,
      api_key: api_key
    } do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["access_token"]
      assert response["token_type"] == "bearer"
      assert response["expires_in"] > 0
      assert response["scope"] == "api"
      # No refresh token for client_credentials
      refute response["refresh_token"]
    end

    test "creates session with access token expiration", %{
      client: client,
      api_key: api_key,
      user: user
    } do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api"
        })

      assert json_response(conn, 200)

      # Verify session was created with short expiration
      sessions = Hexpm.UserSessions.all_for_user(user)
      assert length(sessions) == 1
      [session] = sessions

      # Session should expire within ~30 minutes (allow some margin)
      now = DateTime.utc_now()
      expires_in_seconds = DateTime.diff(session.expires_at, now, :second)
      # At least 25 minutes
      assert expires_in_seconds > 25 * 60
      # At most 30 minutes
      assert expires_in_seconds <= 30 * 60
    end

    test "returns error for missing client_secret", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "scope" => "api"
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_request"
    end

    test "returns error for invalid API key", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => "invalid_key",
          "scope" => "api"
        })

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
    end

    test "returns error for unauthorized grant type", %{api_key: api_key} do
      # Create client that doesn't support client_credentials
      client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Limited OAuth Client",
        client_type: "public",
        allowed_grant_types: ["authorization_code"],
        allowed_scopes: ["api"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api"
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "unauthorized_client"
    end

    test "returns error for invalid scope", %{client: client, api_key: api_key} do
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "invalid_scope"
        })

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert response["error"] == "invalid_scope"
    end

    test "supports custom name parameter", %{
      client: client,
      api_key: api_key,
      user: user
    } do
      name = "Custom Client Name"

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api",
          "name" => name
        })

      assert json_response(conn, 200)

      # Verify session was created with the custom name
      sessions = Hexpm.UserSessions.all_for_user(user)
      [session] = sessions
      assert session.name == name
    end

    test "enforces session limit of 5 per user", %{
      client: client,
      api_key: api_key,
      user: user
    } do
      # Create 5 sessions via client credentials
      for i <- 1..5 do
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api",
          "name" => "Session #{i}"
        })
      end

      # Verify we have 5 sessions
      assert Hexpm.UserSessions.count_for_user(user) == 5

      # Create a 6th session
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api",
          "name" => "Session 6"
        })

      assert json_response(conn, 200)

      # Verify we still only have 5 sessions (oldest was revoked)
      assert Hexpm.UserSessions.count_for_user(user) == 5
    end

    test "expands 'repositories' scope for API key with generic repositories permission", %{
      client: client,
      user: user
    } do
      org = insert(:organization)
      insert(:organization_user, organization: org, user: user)

      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(
          user,
          %{name: "repo_key", permissions: [%{domain: "repositories"}]},
          audit: audit_data(user)
        )

      api_key = key.user_secret

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "repositories"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert response["access_token"]
      # Should include all repositories the user has access to
      scopes = String.split(response["scope"], " ")
      assert "repository:#{org.name}" in scopes
    end

    test "expands 'repositories' scope for API key with specific repository permission", %{
      client: client,
      user: user
    } do
      org = insert(:organization)
      insert(:organization_user, organization: org, user: user)

      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(
          user,
          %{
            name: "specific_repo_key",
            permissions: [%{domain: "repository", resource: org.name}]
          },
          audit: audit_data(user)
        )

      api_key = key.user_secret

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "repositories"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert response["access_token"]
      assert response["scope"] == "repository:#{org.name}"
    end

    test "constrains 'repositories' expansion to API key's specific repository permissions", %{
      client: client,
      user: user
    } do
      org1 = insert(:organization)
      org2 = insert(:organization)
      insert(:organization_user, organization: org1, user: user)
      insert(:organization_user, organization: org2, user: user)

      # API key only has access to org1, not org2
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(
          user,
          %{
            name: "limited_repo_key",
            permissions: [%{domain: "repository", resource: org1.name}]
          },
          audit: audit_data(user)
        )

      api_key = key.user_secret

      # Request "repositories" scope - should only expand to org1, not org2
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "repositories"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert response["access_token"]
      # Should only expand to org1, not org2
      assert response["scope"] == "repository:#{org1.name}"
    end

    test "constrains to multiple specific repositories when key has multiple permissions", %{
      client: client,
      user: user
    } do
      org1 = insert(:organization)
      org2 = insert(:organization)
      org3 = insert(:organization)
      insert(:organization_user, organization: org1, user: user)
      insert(:organization_user, organization: org2, user: user)
      insert(:organization_user, organization: org3, user: user)

      # API key has access to org1 and org2, but not org3
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(
          user,
          %{
            name: "multi_repo_key",
            permissions: [
              %{domain: "repository", resource: org1.name},
              %{domain: "repository", resource: org2.name}
            ]
          },
          audit: audit_data(user)
        )

      api_key = key.user_secret

      # Request "repositories" scope - should expand to org1 and org2, not org3
      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "repositories"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert response["access_token"]
      # Should expand to both org1 and org2
      scopes = String.split(response["scope"], " ")
      assert "repository:#{org1.name}" in scopes
      assert "repository:#{org2.name}" in scopes
      refute "repository:#{org3.name}" in scopes
      assert length(scopes) == 2
    end

    test "supports mixed scopes with repositories", %{
      client: client,
      user: user
    } do
      org = insert(:organization)
      insert(:organization_user, organization: org, user: user)

      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(
          user,
          %{
            name: "mixed_key",
            permissions: [
              %{domain: "api"},
              %{domain: "repositories"}
            ]
          },
          audit: audit_data(user)
        )

      api_key = key.user_secret

      conn =
        post(build_conn(), ~p"/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => api_key,
          "scope" => "api repositories"
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert response["access_token"]
      # Should include api scope and all repository scopes
      scopes = String.split(response["scope"], " ")
      assert "api" in scopes
      assert "repository:#{org.name}" in scopes
    end
  end
end
