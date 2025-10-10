defmodule Hexpm.OAuth.JWTTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.JWT
  alias Hexpm.Accounts.Auth

  describe "generate_access_token/4" do
    test "creates JWT with correct sub claim format" do
      username = "testuser"
      subject_type = "user"
      scopes = ["api", "api:read"]

      {:ok, token, jti} = JWT.generate_access_token(username, subject_type, scopes)

      # Verify we can decode the JWT
      {:ok, claims} = JWT.verify_and_decode(token)

      assert claims["sub"] == "user:testuser"
      assert claims["jti"] == jti
      assert claims["scope"] == "api api:read"
      assert claims["iss"] == "hexpm"
      assert claims["aud"] == "hexpm:api"
    end

    test "creates JWT that can be authenticated by Auth.oauth_token_auth" do
      user = insert(:user, username: "testuser")
      client = insert(:oauth_client)
      oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

      {:ok, oauth_token} =
        Hexpm.OAuth.Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          nil,
          user_session_id: oauth_session.id
        )

      auth_result = Auth.oauth_token_auth(oauth_token.access_token, %{})

      case auth_result do
        {:ok, auth_context} ->
          assert auth_context.user.id == user.id
          assert auth_context.user.username == "testuser"
          assert auth_context.auth_credential.id == oauth_token.id

        other ->
          flunk("Authentication failed with result: #{inspect(other)}")
      end
    end

    test "regression test: ensures sub claim format prevents authentication failure" do
      user = insert(:user, username: "testuser")

      {:ok, access_token, _jti} = JWT.generate_access_token(user.username, "user", ["api"])

      {:ok, claims} = JWT.verify_and_decode(access_token)
      assert claims["sub"] == "user:testuser"

      [subject_type, subject_id] = String.split(claims["sub"], ":", parts: 2)
      assert subject_type == "user"
      assert subject_id == "testuser"
    end
  end

  describe "generate_refresh_token/4" do
    test "creates refresh token with correct sub claim format" do
      username = "testuser"
      subject_type = "user"
      scopes = ["api"]

      {:ok, token, jti} = JWT.generate_refresh_token(username, subject_type, scopes)

      {:ok, claims} = JWT.verify_and_decode(token)

      assert claims["sub"] == "user:testuser"
      assert claims["jti"] == jti
      assert claims["scope"] == "api"
    end
  end

  describe "verify_and_decode/1" do
    test "successfully decodes valid JWT with correct sub format" do
      {:ok, token, _jti} = JWT.generate_access_token("testuser", "user", ["api:read"])

      {:ok, claims} = JWT.verify_and_decode(token)

      assert claims["sub"] == "user:testuser"
      assert claims["scope"] == "api:read"
    end

    test "fails to decode invalid JWT" do
      assert {:error, _reason} = JWT.verify_and_decode("invalid.jwt.token")
    end
  end
end
