defmodule Hexpm.OAuth.DeviceFlowTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.{DeviceFlow, DeviceCode, Token, Client}

  defp create_test_client(name \\ "Test Client") do
    client_params = %{
      client_id: Hexpm.OAuth.Client.generate_client_id(),
      name: name,
      client_type: "public",
      allowed_grant_types: ["urn:ietf:params:oauth:grant-type:device_code"],
      allowed_scopes: ["api", "api:read", "repositories"],
      client_secret: nil
    }

    {:ok, client} = Client.build(client_params) |> Repo.insert()
    client
  end

  describe "initiate_device_authorization/2" do
    test "creates device code with default parameters" do
      client = create_test_client()
      assert {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])

      assert response.device_code
      assert response.user_code
      assert response.verification_uri
      assert response.verification_uri_complete
      assert response.expires_in == 600
      assert response.interval == 5

      # Verify database record was created
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      assert device_code
      assert device_code.client_id == client.client_id
      assert device_code.status == "pending"
      assert device_code.scopes == ["api"]
    end

    test "creates device code with custom scopes" do
      client = create_test_client()
      scopes = ["api:read", "repositories"]
      assert {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, scopes)

      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      assert device_code.scopes == scopes
    end

    test "generates unique codes" do
      client1 = create_test_client("Client 1")
      client2 = create_test_client("Client 2")
      {:ok, response1} = DeviceFlow.initiate_device_authorization(client1.client_id, ["api"])
      {:ok, response2} = DeviceFlow.initiate_device_authorization(client2.client_id, ["api"])

      assert response1.device_code != response2.device_code
      assert response1.user_code != response2.user_code
    end
  end

  describe "poll_device_token/2" do
    setup do
      client = create_test_client()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{device_code: device_code, response: response, client: client}
    end

    test "returns authorization_pending for pending device code", %{
      response: response,
      client: client
    } do
      assert {:error, :authorization_pending, "Authorization pending"} =
               DeviceFlow.poll_device_token(response.device_code, client.client_id)
    end

    test "returns invalid_grant for non-existent device code", %{client: client} do
      assert {:error, :invalid_grant, "Invalid device code"} =
               DeviceFlow.poll_device_token("nonexistent", client.client_id)
    end

    test "returns invalid_client for mismatched client_id", %{response: response} do
      assert {:error, :invalid_client, "Invalid client"} =
               DeviceFlow.poll_device_token(response.device_code, "wrong_client")
    end

    test "returns expired_token for expired device code", %{
      device_code: device_code,
      client: client
    } do
      # Manually expire the device code
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      assert {:error, :expired_token, "Device code has expired"} =
               DeviceFlow.poll_device_token(device_code.device_code, client.client_id)

      # Verify status was updated
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "expired"
    end

    test "returns access_denied for denied device code", %{
      device_code: device_code,
      client: client
    } do
      # Manually deny the device code
      Repo.update!(DeviceCode.deny_changeset(device_code))

      assert {:error, :access_denied, "Authorization denied by user"} =
               DeviceFlow.poll_device_token(device_code.device_code, client.client_id)
    end

    test "returns token for authorized device code", %{device_code: device_code, client: client} do
      user = insert(:user)

      # Authorize the device
      {:ok, _} = DeviceFlow.authorize_device(device_code.user_code, user)

      # Poll for token
      assert {:ok, token_response} =
               DeviceFlow.poll_device_token(device_code.device_code, client.client_id)

      assert token_response.access_token
      assert token_response.token_type == "bearer"
      assert token_response.expires_in > 0
    end
  end

  describe "authorize_device/2" do
    setup do
      client = create_test_client()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      user = insert(:user)
      %{device_code: device_code, user: user, client: client}
    end

    test "successfully authorizes device", %{device_code: device_code, user: user, client: client} do
      assert {:ok, updated_device_code} = DeviceFlow.authorize_device(device_code.user_code, user)

      assert updated_device_code.status == "authorized"
      assert updated_device_code.user_id == user.id

      # Verify OAuth token was created
      oauth_token =
        Repo.get_by(Token,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          grant_reference: device_code.device_code,
          client_id: client.client_id
        )

      assert oauth_token
      assert oauth_token.user_id == user.id
    end

    test "returns error for invalid user code", %{user: user} do
      assert {:error, :invalid_code, "Invalid user code"} =
               DeviceFlow.authorize_device("INVALID", user)
    end

    test "returns error for expired device code", %{device_code: device_code, user: user} do
      # Expire the device code
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      assert {:error, :expired_token, "Device code has expired"} =
               DeviceFlow.authorize_device(device_code.user_code, user)
    end

    test "returns error when device already processed", %{device_code: device_code, user: user} do
      # First authorization
      {:ok, _} = DeviceFlow.authorize_device(device_code.user_code, user)

      # Second authorization attempt
      assert {:error, :invalid_grant, "Device code is not pending authorization"} =
               DeviceFlow.authorize_device(device_code.user_code, user)
    end
  end

  describe "deny_device/1" do
    setup do
      client = create_test_client()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{device_code: device_code, client: client}
    end

    test "successfully denies device", %{device_code: device_code} do
      assert {:ok, updated_device_code} = DeviceFlow.deny_device(device_code.user_code)
      assert updated_device_code.status == "denied"
    end

    test "returns error for invalid user code" do
      assert {:error, :invalid_code, "Invalid user code"} = DeviceFlow.deny_device("INVALID")
    end
  end

  describe "get_device_code_for_verification/1" do
    setup do
      client = create_test_client()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)
      %{device_code: device_code, client: client}
    end

    test "returns device code for valid user code", %{device_code: device_code} do
      assert {:ok, returned_device_code} =
               DeviceFlow.get_device_code_for_verification(device_code.user_code)

      assert returned_device_code.id == device_code.id
    end

    test "returns error for invalid user code" do
      assert {:error, :invalid_code} = DeviceFlow.get_device_code_for_verification("INVALID")
    end

    test "returns error for expired device code", %{device_code: device_code} do
      # Expire the device code
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      assert {:error, :expired} =
               DeviceFlow.get_device_code_for_verification(device_code.user_code)
    end

    test "returns error for already processed device code", %{device_code: device_code} do
      # Mark as authorized
      user = insert(:user)
      DeviceFlow.authorize_device(device_code.user_code, user)

      assert {:error, :already_processed} =
               DeviceFlow.get_device_code_for_verification(device_code.user_code)
    end
  end

  describe "cleanup_expired_device_codes/0" do
    test "marks expired pending device codes as expired" do
      # Create expired device code
      client = create_test_client()
      {:ok, response} = DeviceFlow.initiate_device_authorization(client.client_id, ["api"])
      device_code = Repo.get_by(DeviceCode, device_code: response.device_code)

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(DeviceCode.changeset(device_code, %{expires_at: past_time}))

      # Create non-expired device code
      client2 = create_test_client("Client 2")
      {:ok, _response2} = DeviceFlow.initiate_device_authorization(client2.client_id, ["api"])

      # Run cleanup
      assert {1, nil} = DeviceFlow.cleanup_expired_device_codes()

      # Verify only expired code was updated
      updated_device_code = Repo.get(DeviceCode, device_code.id)
      assert updated_device_code.status == "expired"
    end
  end
end
