defmodule HexpmWeb.API.OAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.{Repo}
  alias Hexpm.OAuth.{DeviceFlow, Client}

  setup do
    # Create test OAuth client
    client_params = %{
      client_id: "test_client_id",
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

    test "uses default scope when none provided", %{client: client} do
      conn =
        post(build_conn(), ~p"/api/oauth/device_authorization", %{
          "client_id" => client.client_id
        })

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response["device_code"])
      assert device_code.scopes == ["api"]
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
          "client_id" => "nonexistent_client"
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
  end

  describe "POST /api/oauth/token with device_code grant" do
    setup %{client: client} do
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
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
      user = create_user()
      {:ok, _} = DeviceFlow.authorize_device(device_code.user_code, user)

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
          "client_id" => "wrong_client"
        })

      assert json_response(conn, 401)
      response_body = json_response(conn, 401)
      assert response_body["error"] == "invalid_client"
    end
  end

  describe "POST /api/oauth/token with refresh_token grant" do
    setup %{client: client} do
      user = create_user()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(Hexpm.OAuth.DeviceCode, device_code: response.device_code)

      # Authorize the device to get a token with refresh token
      {:ok, _} = DeviceFlow.authorize_device(device_code.user_code, user)

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
          "client_id" => "wrong_client"
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
      assert response["error_description"] == "Refresh token expired or revoked"
    end
  end

  defp create_user do
    import Hexpm.Factory
    insert(:user)
  end
end
