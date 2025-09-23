defmodule Hexpm.OAuth.TokenExchangeTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.{Token, TokenExchange, Client, Session}

  describe "exchange_token/4" do
    setup do
      user = insert(:user)

      client_params = %{
        client_id: Hexpm.OAuth.Client.generate_client_id(),
        name: "Test OAuth Client",
        client_type: "public",
        allowed_grant_types: [
          "authorization_code",
          "urn:ietf:params:oauth:grant-type:token-exchange"
        ],
        allowed_scopes: ["api", "api:read", "api:write", "repositories"]
      }

      {:ok, client} = Client.build(client_params) |> Repo.insert()

      # Create parent token with multiple scopes

      {:ok, session} = Repo.insert(Session.create_for_user(user, client.client_id))

      parent_token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true
        )

      {:ok, parent_token} = Repo.insert(parent_token_changeset)

      %{
        user: user,
        client: client,
        parent_token: parent_token
      }
    end

    test "successfully exchanges token with subset scopes", %{
      client: client,
      parent_token: parent_token
    } do
      target_scopes = ["api:read", "repositories"]

      assert {:ok, new_token} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 target_scopes
               )

      assert new_token.scopes == target_scopes
      assert new_token.grant_type == "urn:ietf:params:oauth:grant-type:token-exchange"
      assert new_token.parent_token_id == parent_token.id
      assert new_token.session_id == parent_token.session_id
      assert new_token.user_id == parent_token.user_id
      assert new_token.client_id == parent_token.client_id
      assert not is_nil(new_token.refresh_token)
    end

    test "exchanges token with single scope", %{client: client, parent_token: parent_token} do
      target_scopes = ["api:read"]

      assert {:ok, new_token} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 target_scopes
               )

      assert new_token.scopes == target_scopes
    end

    test "accepts string scope parameter", %{client: client, parent_token: parent_token} do
      target_scopes = "api:read repositories"

      assert {:ok, new_token} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 target_scopes
               )

      assert new_token.scopes == ["api:read", "repositories"]
    end

    test "fails with invalid client", %{parent_token: parent_token} do
      assert {:error, :invalid_client, "Invalid client"} =
               TokenExchange.exchange_token(
                 Ecto.UUID.generate(),
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 ["api:read"]
               )
    end

    test "fails with invalid subject token", %{client: client} do
      assert {:error, :invalid_grant, "Invalid subject token"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 "invalid_token",
                 "urn:ietf:params:oauth:token-type:access_token",
                 ["api:read"]
               )
    end

    test "fails with unsupported subject token type", %{
      client: client,
      parent_token: parent_token
    } do
      assert {:error, :invalid_request, "Unsupported subject_token_type: " <> _} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "unsupported_type",
                 ["api:read"]
               )
    end

    test "fails when target scopes exceed parent scopes", %{
      client: client,
      parent_token: parent_token
    } do
      # Parent has ["api:read", "api:write", "repositories"]
      # Trying to get broader "api" scope
      target_scopes = ["api"]

      assert {:error, :invalid_scope, "target scopes must be subset of source scopes"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 target_scopes
               )
    end

    test "fails when target includes scopes not in parent", %{
      client: client,
      parent_token: parent_token
    } do
      # Parent doesn't have "package" scope
      target_scopes = ["api:read", "package"]

      assert {:error, :invalid_scope, "target scopes must be subset of source scopes"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 target_scopes
               )
    end

    test "fails with missing scope parameter", %{client: client, parent_token: parent_token} do
      assert {:error, :invalid_request, "Missing required parameter: scope"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 nil
               )
    end

    test "fails with expired parent token", %{client: client, user: user} do
      {:ok, session} = Repo.insert(Session.create_for_user(user, client.client_id))

      # Create expired token
      expired_token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          # expired 1 hour ago
          expires_in: -3600
        )

      {:ok, expired_token} = Repo.insert(expired_token_changeset)

      assert {:error, :invalid_grant, "Subject token expired or revoked"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 expired_token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 ["api:read"]
               )
    end

    test "fails with revoked parent token", %{client: client, user: user} do
      {:ok, session} = Repo.insert(Session.create_for_user(user, client.client_id))

      # Create and revoke token
      token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id
        )

      {:ok, token} = Repo.insert(token_changeset)
      {:ok, _revoked_token} = Repo.update(Token.revoke(token))

      assert {:error, :invalid_grant, "Subject token expired or revoked"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 token.access_token,
                 "urn:ietf:params:oauth:token-type:access_token",
                 ["api:read"]
               )
    end

    test "successfully exchanges refresh token with subset scopes", %{
      client: client,
      parent_token: parent_token
    } do
      target_scopes = ["api:read"]

      assert {:ok, new_token} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.refresh_token,
                 "urn:ietf:params:oauth:token-type:refresh_token",
                 target_scopes
               )

      assert new_token.scopes == target_scopes
      assert new_token.grant_type == "urn:ietf:params:oauth:grant-type:token-exchange"
      assert new_token.parent_token_id == parent_token.id
      assert new_token.session_id == parent_token.session_id
      assert new_token.user_id == parent_token.user_id
      assert new_token.client_id == parent_token.client_id
      assert not is_nil(new_token.refresh_token)
    end

    test "fails with invalid refresh token", %{client: client} do
      invalid_refresh_token = "invalid_refresh_token_value"

      assert {:error, :invalid_grant, "Invalid subject token"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 invalid_refresh_token,
                 "urn:ietf:params:oauth:token-type:refresh_token",
                 ["api:read"]
               )
    end

    test "fails with expired token when using refresh token", %{client: client, user: user} do
      {:ok, session} = Repo.insert(Session.create_for_user(user, client.client_id))

      # Create expired token with refresh token
      expired_token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true,
          expires_in: -3600
        )

      {:ok, expired_token} = Repo.insert(expired_token_changeset)

      assert {:error, :invalid_grant, "Subject token expired or revoked"} =
               TokenExchange.exchange_token(
                 client.client_id,
                 expired_token.refresh_token,
                 "urn:ietf:params:oauth:token-type:refresh_token",
                 ["api:read"]
               )
    end

    test "fails with unsupported token type", %{client: client, parent_token: parent_token} do
      assert {:error, :invalid_request, "Unsupported subject_token_type: " <> _} =
               TokenExchange.exchange_token(
                 client.client_id,
                 parent_token.access_token,
                 "urn:ietf:params:oauth:token-type:id_token",
                 ["api:read"]
               )
    end
  end
end
