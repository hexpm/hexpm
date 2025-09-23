defmodule HexpmWeb.API.OAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.{Repo}
  alias Hexpm.OAuth.{DeviceCodes, Client, Clients, Sessions, Token, Tokens}

  setup do
    # Create test OAuth client
    client_params = %{
      client_id: Clients.generate_client_id(),
      name: "Test OAuth Client",
      client_type: "public",
      allowed_grant_types: ["urn:ietf:params:oauth:grant-type:device_code"],
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

      assert json_response(conn, 401)
      response = json_response(conn, 401)
      assert response["error"] == "invalid_client"
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

    test "handles erlang format requests", %{client: client} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/vnd.hex+erlang")
        |> post(~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id,
          "scope" => "api"
        })

      assert response = response(conn, 200)
      erlang_term = :erlang.binary_to_term(response, [:safe])

      assert is_map(erlang_term)
      assert Map.has_key?(erlang_term, "device_code")
      assert Map.has_key?(erlang_term, "user_code")
      assert Map.has_key?(erlang_term, "verification_uri")
      assert Map.has_key?(erlang_term, "expires_in")
      assert Map.has_key?(erlang_term, "interval")
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
      {:ok, _} = DeviceCodes.authorize_device(device_code.user_code, user)

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
      {:ok, _} = DeviceCodes.authorize_device(device_code.user_code, user)

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
      {:ok, session} = Sessions.create_for_user(user, client.client_id)

      # Create a token with an expired refresh token
      token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true
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
        allowed_grant_types: [
          "authorization_code",
          "urn:ietf:params:oauth:grant-type:token-exchange"
        ],
        allowed_scopes: ["api", "api:read", "api:write", "repositories"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      {:ok, session} = Sessions.create_for_user(user, client.client_id)

      # Create parent token with refresh token
      parent_token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true
        )

      {:ok, parent_token} = Repo.insert(parent_token_changeset)
      parent_token = Repo.preload(parent_token, :user)

      # Extract token values from the inserted token with virtual fields
      parent_tokens = %{
        access_token: parent_token.access_token,
        refresh_token: parent_token.refresh_token
      }

      # Create child tokens
      child1_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Extract child token values from virtual fields
      child1_tokens = %{access_token: child1.access_token, refresh_token: child1.refresh_token}
      child2_tokens = %{access_token: child2.access_token, refresh_token: child2.refresh_token}

      %{
        revoke_user: user,
        revoke_client: client,
        revoke_parent_token: parent_token,
        revoke_parent_tokens: parent_tokens,
        revoke_child1: child1,
        revoke_child1_tokens: child1_tokens,
        revoke_child2: child2,
        revoke_child2_tokens: child2_tokens
      }
    end

    test "successfully revokes individual access token", %{
      revoke_client: client,
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens,
      revoke_child1: child1,
      revoke_child2: child2
    } do
      params = %{
        token: parent_tokens.access_token,
        client_id: client.client_id
      }

      # Should return 200 OK per RFC 7009
      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Only the parent token should be revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Tokens.revoked?(updated_parent)
      refute Tokens.revoked?(updated_child1)
      refute Tokens.revoked?(updated_child2)
    end

    test "successfully revokes individual refresh token", %{
      revoke_client: client,
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens,
      revoke_child1: child1,
      revoke_child2: child2
    } do
      params = %{
        token: parent_tokens.refresh_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Only the parent token should be revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Tokens.revoked?(updated_parent)
      refute Tokens.revoked?(updated_child1)
      refute Tokens.revoked?(updated_child2)
    end

    test "revokes child token only affects that child", %{
      revoke_client: client,
      revoke_parent_token: parent_token,
      revoke_child1: child1,
      revoke_child1_tokens: child1_tokens,
      revoke_child2: child2
    } do
      params = %{
        token: child1_tokens.access_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Check only child1 is revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      refute Tokens.revoked?(updated_parent)
      assert Tokens.revoked?(updated_child1)
      refute Tokens.revoked?(updated_child2)
    end

    test "returns 200 OK for invalid token (security per RFC 7009)", %{
      revoke_client: client
    } do
      params = %{
        token: "invalid_token_value",
        client_id: client.client_id
      }

      # Should still return 200 OK to avoid leaking information
      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for invalid client_id (security per RFC 7009)", %{
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens
    } do
      params = %{
        token: parent_tokens.access_token,
        client_id: Ecto.UUID.generate()
      }

      # Should still return 200 OK to avoid leaking information
      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Token should not be revoked
      updated_token = Repo.get(Token, parent_token.id)
      refute Tokens.revoked?(updated_token)
    end

    test "returns 200 OK for missing parameters" do
      # Missing both token and client_id
      params = %{}

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for missing token parameter", %{revoke_client: client} do
      params = %{
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "returns 200 OK for missing client_id parameter", %{
      revoke_parent_tokens: parent_tokens
    } do
      params = %{
        token: parent_tokens.access_token
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "handles revocation of already revoked token", %{
      revoke_client: client,
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens
    } do
      # First revoke the token
      {:ok, _} = Tokens.revoke(parent_token)

      # Try to revoke again
      params = %{
        token: parent_tokens.access_token,
        client_id: client.client_id
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)
    end

    test "handles token from different client", %{
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens
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
        token: parent_tokens.access_token,
        client_id: other_client.client_id
      }

      # Should return 200 OK but not revoke the token
      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Token should not be revoked
      updated_token = Repo.get(Token, parent_token.id)
      refute Tokens.revoked?(updated_token)
    end

    test "supports token_type_hint parameter (optional per RFC 7009)", %{
      revoke_client: client,
      revoke_parent_token: parent_token,
      revoke_parent_tokens: parent_tokens
    } do
      params = %{
        token: parent_tokens.access_token,
        client_id: client.client_id,
        token_type_hint: "access_token"
      }

      build_conn()
      |> post(~p"/api/oauth/revoke", params)
      |> response(200)

      # Token should be revoked
      updated_token = Repo.get(Token, parent_token.id)
      assert Tokens.revoked?(updated_token)
    end
  end

  describe "POST /api/oauth/token with token-exchange grant" do
    setup do
      user = insert(:user)

      client_params = %{
        client_id: Clients.generate_client_id(),
        name: "Test OAuth Client",
        client_type: "public",
        allowed_grant_types: [
          "authorization_code",
          "urn:ietf:params:oauth:grant-type:token-exchange"
        ],
        allowed_scopes: ["api", "api:read", "api:write", "repositories"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      {:ok, session} = Sessions.create_for_user(user, client.client_id)

      # Create parent token
      parent_token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true
        )

      {:ok, parent_token} = Repo.insert(parent_token_changeset)
      parent_token = Repo.preload(parent_token, :user)

      # Extract token values from virtual fields
      parent_tokens = %{
        access_token: parent_token.access_token,
        refresh_token: parent_token.refresh_token
      }

      %{
        exchange_user: user,
        exchange_client: client,
        exchange_parent_token: parent_token,
        exchange_parent_tokens: parent_tokens
      }
    end

    test "successfully exchanges token with valid parameters", %{
      exchange_client: client,
      exchange_parent_token: parent_token,
      exchange_parent_tokens: parent_tokens
    } do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: parent_tokens.access_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: "api:read repositories"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(200)

      assert %{
               "access_token" => access_token,
               "token_type" => "bearer",
               "expires_in" => expires_in,
               "scope" => "api:read repositories",
               "refresh_token" => refresh_token
             } = response

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert is_integer(expires_in)
      assert expires_in > 0

      # Verify token was created in database
      {:ok, created_token} =
        Tokens.lookup(access_token, :access, client_id: client.client_id, preload: [])

      assert created_token.scopes == ["api:read", "repositories"]
      assert created_token.parent_token_id == parent_token.id
      assert created_token.session_id == parent_token.session_id
    end

    test "fails with invalid client_id", %{exchange_parent_tokens: parent_tokens} do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: Ecto.UUID.generate(),
        subject_token: parent_tokens.access_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: "api:read"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(401)

      assert %{
               "error" => "invalid_client",
               "error_description" => "Invalid client"
             } = response
    end

    test "fails with invalid subject_token", %{exchange_client: client} do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: "invalid_token",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: "api:read"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(400)

      assert %{
               "error" => "invalid_grant",
               "error_description" => "Invalid subject token"
             } = response
    end

    test "fails with unsupported subject_token_type", %{
      exchange_client: client,
      exchange_parent_tokens: parent_tokens
    } do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: parent_tokens.access_token,
        subject_token_type: "unsupported_type",
        scope: "api:read"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(400)

      assert %{
               "error" => "invalid_request",
               "error_description" => "Unsupported subject_token_type: unsupported_type"
             } = response
    end

    test "fails when target scopes exceed parent scopes", %{
      exchange_client: client,
      exchange_parent_tokens: parent_tokens
    } do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: parent_tokens.access_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: "api"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(400)

      assert %{
               "error" => "invalid_scope",
               "error_description" => "target scopes must be subset of source scopes"
             } = response
    end

    test "fails with missing scope parameter", %{
      exchange_client: client,
      exchange_parent_tokens: parent_tokens
    } do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: parent_tokens.access_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(400)

      assert %{
               "error" => "invalid_request",
               "error_description" => "Missing required parameter: scope"
             } = response
    end

    test "handles token exchange with single scope", %{
      exchange_client: client,
      exchange_parent_tokens: parent_tokens
    } do
      params = %{
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        client_id: client.client_id,
        subject_token: parent_tokens.access_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: "api:read"
      }

      response =
        build_conn()
        |> post(~p"/api/oauth/token", params)
        |> json_response(200)

      assert %{
               "scope" => "api:read"
             } = response

      # Verify token in database
      {:ok, created_token} =
        Tokens.lookup(response["access_token"], :access, client_id: client.client_id, preload: [])

      assert created_token.scopes == ["api:read"]
    end
  end
end
