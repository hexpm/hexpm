defmodule Hexpm.Accounts.AuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Auth, Key}

  setup do
    user = insert(:user, password: Auth.gen_password("password"))
    %{user: user, password: "password"}
  end

  describe "password_auth/2" do
    test "authorizes correct password", %{user: user, password: password} do
      assert {:ok,
              %{
                user: auth_user,
                email: email,
                auth_credential: auth_credential,
                organization: organization
              }} =
               Auth.password_auth(user.username, password)

      assert auth_user.id == user.id
      assert email.id == hd(user.emails).id
      assert auth_credential == nil
      assert organization == nil
    end

    test "does not authorize wrong password", %{user: user, password: password} do
      assert Auth.password_auth("some_invalid_username", password) == :error
      assert Auth.password_auth(user.username, "some_wrong_password") == :error
    end
  end

  describe "key_auth/2" do
    test "authorizes correct key", %{user: user} do
      key = insert(:key, user: user)

      assert {:ok,
              %{
                user: auth_user,
                auth_credential: auth_key,
                email: email,
                organization: organization
              }} =
               Auth.key_auth(key.user_secret, %{})

      assert auth_key.id == key.id
      assert auth_user.id == user.id
      assert email.id == hd(user.emails).id
      assert organization == nil
    end

    test "stores key usage information when used", %{user: user} do
      key = insert(:key, user: user)
      timestamp = DateTime.utc_now()

      usage_info = %{
        used_at: timestamp,
        user_agent: ["Chrome"],
        ip: {127, 0, 0, 1}
      }

      {:ok, _} = Auth.key_auth(key.user_secret, usage_info)

      key = Repo.get(Key, key.id)
      assert key.last_use.used_at == timestamp
      assert key.last_use.user_agent == "Chrome"
      assert key.last_use.ip == "127.0.0.1"
    end

    test "does not authorize wrong key" do
      assert Auth.key_auth("0123456789abcdef", %{}) == :error
    end

    test "does not authorize revoked key", %{user: user} do
      key = insert(:key, user: user, revoke_at: ~N"2017-01-01 00:00:00")
      assert Auth.key_auth(key.user_secret, %{}) == :revoked
    end
  end

  describe "oauth_token_auth/2" do
    test "authenticates with valid JWT token" do
      user = insert(:user, username: "oauth_test_user")

      # Create OAuth client and session
      client = insert(:oauth_client)
      oauth_session = insert(:oauth_session, user: user, client_id: client.client_id)

      # Create OAuth token using the Tokens module (which now generates correct JWT format)
      {:ok, oauth_token} =
        Hexpm.OAuth.Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api", "api:read"],
          "authorization_code",
          "test_grant_ref",
          session_id: oauth_session.id
        )

      auth_result = Auth.oauth_token_auth(oauth_token.access_token, %{})

      case auth_result do
        {:ok, auth_context} ->
          assert auth_context.user.id == user.id
          assert auth_context.user.username == "oauth_test_user"
          assert auth_context.auth_credential.id == oauth_token.id
          assert auth_context.organization == nil
          assert is_nil(auth_context.email) or auth_context.email.user_id == user.id

        other ->
          flunk("OAuth token authentication failed with result: #{inspect(other)}")
      end
    end

    test "fails with invalid JWT token" do
      auth_result = Auth.oauth_token_auth("invalid.jwt.token", %{})
      assert auth_result == :error
    end

    test "fails with malformed JWT token" do
      auth_result = Auth.oauth_token_auth("not-a-jwt", %{})
      assert auth_result == :error
    end

    test "regression test: documents correct JWT sub format for authentication" do
      user = insert(:user, username: "regression_user")

      # Generate JWT using our fixed implementation
      {:ok, access_token, _jti} =
        Hexpm.OAuth.JWT.generate_access_token(user.username, "user", ["api"])

      # Verify the sub claim has the CORRECT format
      {:ok, claims} = Hexpm.OAuth.JWT.verify_and_decode(access_token)
      assert claims["sub"] == "user:regression_user"

      # Verify this format can be parsed correctly (indirectly tests parse_subject)
      [subject_type, subject_id] = String.split(claims["sub"], ":", parts: 2)
      assert subject_type == "user"
      assert subject_id == "regression_user"
    end
  end
end
