defmodule Hexpm.OAuth.TokenTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.Token

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Token.changeset(%Token{}, %{})

      assert %{
               token_first: "can't be blank",
               token_second: "can't be blank",
               token_hash: "can't be blank",
               expires_at: "can't be blank",
               grant_type: "can't be blank",
               user_id: "can't be blank",
               client_id: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates grant type inclusion" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      changeset =
        Token.changeset(%Token{}, %{
          token_first: "first",
          token_second: "second",
          token_hash: "hash",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: expires_at,
          grant_type: "invalid_grant",
          user_id: user.id,
          client_id: "test_client"
        })

      assert %{grant_type: "is invalid"} = errors_on(changeset)
    end

    test "validates scopes" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      changeset =
        Token.changeset(%Token{}, %{
          token_first: "first",
          token_second: "second",
          token_hash: "hash",
          token_type: "bearer",
          scopes: ["invalid_scope", "api"],
          expires_at: expires_at,
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: "test_client"
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        token_first: "first",
        token_second: "second",
        token_hash: "hash",
        token_type: "bearer",
        refresh_token_first: "rf_first",
        refresh_token_second: "rf_second",
        refresh_token_hash: "rf_hash",
        scopes: ["api", "api:read"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        grant_reference: "auth_code_123",
        user_id: user.id,
        client_id: "test_client"
      }

      changeset = Token.changeset(%Token{}, attrs)
      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds token with valid attributes" do
      user = create_user()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        token_first: "first",
        token_second: "second",
        token_hash: "hash",
        token_type: "bearer",
        scopes: ["api"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        user_id: user.id,
        client_id: "test_client"
      }

      changeset = Token.build(attrs)
      assert changeset.valid?
    end
  end

  describe "generate_access_token/0" do
    test "generates three-part token with correct format" do
      {user_token, first, second} = Token.generate_access_token()

      assert is_binary(user_token)
      assert is_binary(first)
      assert is_binary(second)

      # User token should be base64url without padding
      refute String.contains?(user_token, "=")
      assert String.length(user_token) > 0

      # First and second should be 32-character hex strings
      assert String.length(first) == 32
      assert String.length(second) == 32
      assert Regex.match?(~r/^[0-9a-f]+$/, first)
      assert Regex.match?(~r/^[0-9a-f]+$/, second)
    end

    test "generates unique tokens" do
      {user_token1, first1, second1} = Token.generate_access_token()
      {user_token2, first2, second2} = Token.generate_access_token()

      assert user_token1 != user_token2
      assert first1 != first2
      assert second1 != second2
    end

    test "generates consistent splits for same input" do
      # This tests the deterministic nature of HMAC
      user_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      app_secret = Application.get_env(:hexpm, :secret)

      # Generate split twice with same input
      <<first1::binary-size(32), second1::binary-size(32)>> =
        :crypto.mac(:hmac, :sha256, app_secret, user_token)
        |> Base.encode16(case: :lower)

      <<first2::binary-size(32), second2::binary-size(32)>> =
        :crypto.mac(:hmac, :sha256, app_secret, user_token)
        |> Base.encode16(case: :lower)

      assert first1 == first2
      assert second1 == second2
    end
  end

  describe "generate_refresh_token/0" do
    test "generates three-part refresh token with correct format" do
      {user_token, first, second} = Token.generate_refresh_token()

      assert is_binary(user_token)
      assert is_binary(first)
      assert is_binary(second)

      # User token should be base64url without padding
      refute String.contains?(user_token, "=")
      assert String.length(user_token) > 0

      # First and second should be 32-character hex strings
      assert String.length(first) == 32
      assert String.length(second) == 32
      assert Regex.match?(~r/^[0-9a-f]+$/, first)
      assert Regex.match?(~r/^[0-9a-f]+$/, second)
    end

    test "generates unique refresh tokens" do
      {user_token1, first1, second1} = Token.generate_refresh_token()
      {user_token2, first2, second2} = Token.generate_refresh_token()

      assert user_token1 != user_token2
      assert first1 != first2
      assert second1 != second2
    end
  end

  describe "create_for_user/6" do
    setup do
      user = create_user()
      %{user: user}
    end

    test "creates changeset with required fields", %{user: user} do
      changeset =
        Token.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          "auth_code_123"
        )

      assert changeset.valid?
      assert get_field(changeset, :token_first)
      assert get_field(changeset, :token_second)
      assert get_field(changeset, :token_hash)
      assert get_field(changeset, :scopes) == ["api"]
      assert get_field(changeset, :grant_type) == "authorization_code"
      assert get_field(changeset, :grant_reference) == "auth_code_123"
      assert get_field(changeset, :user_id) == user.id
      assert get_field(changeset, :client_id) == "test_client"
      assert get_field(changeset, :expires_at)
      refute get_field(changeset, :refresh_token_first)
    end

    test "sets custom expiration time", %{user: user} do
      changeset =
        Token.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          nil,
          expires_in: 7200
        )

      expires_at = get_field(changeset, :expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 7200, :second)

      # Allow 1 second tolerance for test execution time
      assert DateTime.diff(expires_at, expected_time, :second) |> abs() <= 1
    end

    test "creates refresh token when requested", %{user: user} do
      changeset =
        Token.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      assert get_field(changeset, :refresh_token_first)
      assert get_field(changeset, :refresh_token_second)
      assert get_field(changeset, :refresh_token_hash)
    end

    test "defaults grant_reference to nil", %{user: user} do
      changeset =
        Token.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code"
        )

      assert get_field(changeset, :grant_reference) == nil
    end
  end

  describe "expired?/1" do
    test "returns false for non-expired token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time}

      refute Token.expired?(token)
    end

    test "returns true for expired token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{expires_at: past_time}

      assert Token.expired?(token)
    end
  end

  describe "revoked?/1" do
    test "returns false for non-revoked token" do
      token = %Token{revoked_at: nil}

      refute Token.revoked?(token)
    end

    test "returns true for revoked token" do
      token = %Token{revoked_at: DateTime.utc_now()}

      assert Token.revoked?(token)
    end
  end

  describe "valid?/1" do
    test "returns true for non-expired, non-revoked token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time, revoked_at: nil}

      assert Token.valid?(token)
    end

    test "returns false for expired token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{expires_at: past_time, revoked_at: nil}

      refute Token.valid?(token)
    end

    test "returns false for revoked token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time, revoked_at: DateTime.utc_now()}

      refute Token.valid?(token)
    end
  end

  describe "revoke/1" do
    test "creates changeset with revoked_at timestamp" do
      token = %Token{}
      changeset = Token.revoke(token)

      revoked_at = get_field(changeset, :revoked_at)
      assert revoked_at
      # Should be within last few seconds
      assert DateTime.diff(DateTime.utc_now(), revoked_at, :second) <= 1
    end
  end

  describe "has_scopes?/2" do
    test "returns true when token has all required scopes" do
      token = %Token{scopes: ["api", "api:read", "api:write"]}

      assert Token.has_scopes?(token, ["api"])
      assert Token.has_scopes?(token, ["api", "api:read"])
      assert Token.has_scopes?(token, ["api:read", "api:write"])
      assert Token.has_scopes?(token, [])
    end

    test "returns false when token missing required scopes" do
      token = %Token{scopes: ["api", "api:read"]}

      refute Token.has_scopes?(token, ["api:write"])
      refute Token.has_scopes?(token, ["api", "repositories"])
      refute Token.has_scopes?(token, ["invalid_scope"])
    end
  end

  describe "to_response/1" do
    test "creates basic response without refresh token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      token = %Token{
        token_hash: "access_token_123",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api", "api:read"],
        refresh_token_hash: nil
      }

      response = Token.to_response(token)

      assert response.access_token == "access_token_123"
      assert response.token_type == "bearer"
      assert response.expires_in > 3590 and response.expires_in <= 3600
      assert response.scope == "api api:read"
      refute Map.has_key?(response, :refresh_token)
    end

    test "includes refresh token when present" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      token = %Token{
        token_hash: "access_token_123",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api"],
        refresh_token_hash: "refresh_token_456"
      }

      response = Token.to_response(token)

      assert response.access_token == "access_token_123"
      assert response.refresh_token == "refresh_token_456"
    end

    test "handles expired token gracefully" do
      past_time = DateTime.add(DateTime.utc_now(), -100, :second)

      token = %Token{
        token_hash: "access_token_123",
        token_type: "bearer",
        expires_at: past_time,
        scopes: ["api"],
        refresh_token_hash: nil
      }

      response = Token.to_response(token)

      assert response.expires_in == 0
    end
  end

  describe "verify_permissions?/3" do
    test "validates api domain permissions" do
      token_api = %Token{scopes: ["api"]}
      token_read = %Token{scopes: ["api:read"]}
      token_write = %Token{scopes: ["api:write"]}

      # "api" scope allows all api operations
      assert Token.verify_permissions?(token_api, "api", nil)
      assert Token.verify_permissions?(token_api, "api", "read")
      assert Token.verify_permissions?(token_api, "api", "write")

      # "api:read" scope allows read operations
      assert Token.verify_permissions?(token_read, "api", nil)
      assert Token.verify_permissions?(token_read, "api", "read")
      refute Token.verify_permissions?(token_read, "api", "write")

      # "api:write" scope allows read and write operations
      assert Token.verify_permissions?(token_write, "api", nil)
      assert Token.verify_permissions?(token_write, "api", "read")
      assert Token.verify_permissions?(token_write, "api", "write")
    end

    test "validates package domain permissions" do
      token_api = %Token{scopes: ["api"]}
      token_write = %Token{scopes: ["api:write"]}
      token_read = %Token{scopes: ["api:read"]}

      # "api" and "api:write" scopes allow package access
      assert Token.verify_permissions?(token_api, "package", nil)
      assert Token.verify_permissions?(token_write, "package", nil)

      # "api:read" does not allow package access
      refute Token.verify_permissions?(token_read, "package", nil)
    end

    test "denies unknown domains" do
      token = %Token{scopes: ["api"]}

      refute Token.verify_permissions?(token, "unknown", nil)
      refute Token.verify_permissions?(token, "repositories", "read")
    end

    test "requires matching scopes" do
      token_empty = %Token{scopes: []}
      token_repo = %Token{scopes: ["repositories"]}

      refute Token.verify_permissions?(token_empty, "api", nil)
      refute Token.verify_permissions?(token_repo, "api", nil)
    end
  end

  defp create_user do
    import Hexpm.Factory
    insert(:user)
  end
end
