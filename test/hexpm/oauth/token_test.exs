defmodule Hexpm.OAuth.TokenTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{Token, Client}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Token.changeset(%Token{}, %{})

      assert %{
               token_first: "can't be blank",
               token_second: "can't be blank",
               expires_at: "can't be blank",
               grant_type: "can't be blank",
               user_id: "can't be blank",
               client_id: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates grant type inclusion" do
      user = insert(:user)
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
          client_id: Hexpm.OAuth.Client.generate_client_id()
        })

      assert %{grant_type: "is invalid"} = errors_on(changeset)
    end

    test "validates scopes" do
      user = insert(:user)
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
          client_id: Hexpm.OAuth.Client.generate_client_id()
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = insert(:user)
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
      user = insert(:user)
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
      user = insert(:user)
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
      assert get_field(changeset, :access_token)
      assert get_field(changeset, :scopes) == ["api"]
      assert get_field(changeset, :grant_type) == "authorization_code"
      assert get_field(changeset, :grant_reference) == "auth_code_123"
      assert get_field(changeset, :user_id) == user.id
      assert get_field(changeset, :client_id) == "test_client"
      assert get_field(changeset, :expires_at)
      refute get_field(changeset, :refresh_token_first)
      refute get_field(changeset, :refresh_token)
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
      assert get_field(changeset, :refresh_token)
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
        access_token: "access_token_123",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api", "api:read"]
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
        access_token: "access_token_123",
        refresh_token: "refresh_token_456",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api"]
      }

      response = Token.to_response(token)

      assert response.access_token == "access_token_123"
      assert response.refresh_token == "refresh_token_456"
    end

    test "handles expired token gracefully" do
      past_time = DateTime.add(DateTime.utc_now(), -100, :second)

      token = %Token{
        access_token: "access_token_123",
        token_type: "bearer",
        expires_at: past_time,
        scopes: ["api"]
      }

      response = Token.to_response(token)

      assert response.expires_in == 0
    end
  end

  describe "verify_permissions?/3" do
    test "validates api domain permissions" do
      alias Hexpm.Permissions

      token_api = %Token{scopes: ["api"]}
      token_read = %Token{scopes: ["api:read"]}
      token_write = %Token{scopes: ["api:write"]}

      # "api" scope allows all api operations
      assert Permissions.verify_access?(token_api, "api", nil)
      assert Permissions.verify_access?(token_api, "api", "read")
      assert Permissions.verify_access?(token_api, "api", "write")

      # "api:read" scope allows read operations
      assert Permissions.verify_access?(token_read, "api", nil)
      assert Permissions.verify_access?(token_read, "api", "read")
      refute Permissions.verify_access?(token_read, "api", "write")

      # "api:write" scope allows read and write operations
      assert Permissions.verify_access?(token_write, "api", nil)
      assert Permissions.verify_access?(token_write, "api", "read")
      assert Permissions.verify_access?(token_write, "api", "write")
    end

    test "validates package domain permissions" do
      alias Hexpm.Permissions

      token_api = %Token{scopes: ["api"]}
      token_write = %Token{scopes: ["api:write"]}
      token_read = %Token{scopes: ["api:read"]}

      # "api" and "api:write" scopes allow package access
      assert Permissions.verify_access?(token_api, "package", nil)
      assert Permissions.verify_access?(token_write, "package", nil)

      # "api:read" does not allow package access
      refute Permissions.verify_access?(token_read, "package", nil)
    end

    test "denies unknown domains" do
      alias Hexpm.Permissions

      token = %Token{scopes: ["api"]}

      refute Permissions.verify_access?(token, "unknown", nil)
      refute Permissions.verify_access?(token, "repositories", "read")
    end

    test "requires matching scopes" do
      alias Hexpm.Permissions

      token_empty = %Token{scopes: []}
      token_repo = %Token{scopes: ["repositories"]}

      refute Permissions.verify_access?(token_empty, "api", nil)
      refute Permissions.verify_access?(token_repo, "api", nil)
    end
  end

  describe "token hierarchy and revocation" do
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

      # Create parent token
      parent_token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          "test_code",
          with_refresh_token: true
        )

      {:ok, parent_token} = Repo.insert(parent_token_changeset)
      parent_token = Repo.preload(parent_token, :user)

      %{
        user: user,
        client: client,
        parent_token: parent_token
      }
    end

    test "create_exchanged_token/4 creates child token with correct relationships", %{
      parent_token: parent_token,
      client: client
    } do
      target_scopes = ["api:read", "repositories"]

      child_token_changeset =
        Token.create_exchanged_token(
          parent_token,
          client.client_id,
          target_scopes,
          "exchange_grant_ref"
        )

      {:ok, child_token} = Repo.insert(child_token_changeset)

      assert child_token.parent_token_id == parent_token.id
      assert child_token.token_family_id == parent_token.token_family_id
      assert child_token.scopes == target_scopes
      assert child_token.grant_type == "urn:ietf:params:oauth:grant-type:token-exchange"
      assert child_token.grant_reference == "exchange_grant_ref"
      assert child_token.user_id == parent_token.user_id
      assert child_token.client_id == parent_token.client_id
      assert not is_nil(child_token.refresh_token_first)
    end

    test "revoke/1 on parent token cascades to entire family", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Revoke parent token (should cascade)
      assert {:ok, _} = Token.revoke_token(parent_token)

      # Check all tokens in family are revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Token.revoked?(updated_parent)
      assert Token.revoked?(updated_child1)
      assert Token.revoked?(updated_child2)
    end

    test "revoke/1 on child token only revokes that child", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Revoke only child1
      assert {:ok, _} = Token.revoke_token(child1)

      # Check only child1 is revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      refute Token.revoked?(updated_parent)
      assert Token.revoked?(updated_child1)
      refute Token.revoked?(updated_child2)
    end

    test "token exchange always creates children of root token", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child token from parent
      child1_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      {:ok, child1} = Repo.insert(child1_changeset)

      # Create another token from child1 (should still have parent as root)
      child1_with_user = Repo.preload(child1, :user)

      child2_changeset =
        Token.create_exchanged_token(child1_with_user, client.client_id, ["api:read"], "ref2")

      {:ok, child2} = Repo.insert(child2_changeset)

      # Both children should have the root token as their parent
      assert child1.parent_token_id == parent_token.id
      assert child2.parent_token_id == parent_token.id
      assert child1.token_family_id == parent_token.token_family_id
      assert child2.token_family_id == parent_token.token_family_id
    end

    test "cascade_revoke/1 revokes all tokens in family", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Token.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Manually call cascade_revoke
      {revoked_count, _} = Token.cascade_revoke(parent_token)

      # Should revoke all 3 tokens
      assert revoked_count == 3

      # Check all tokens are revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Token.revoked?(updated_parent)
      assert Token.revoked?(updated_child1)
      assert Token.revoked?(updated_child2)
    end

    test "generate_family_id/0 creates unique IDs" do
      id1 = Token.generate_family_id()
      id2 = Token.generate_family_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
      assert String.length(id1) > 0
      assert String.length(id2) > 0
    end

    test "create_for_user with parent token uses same family_id", %{
      parent_token: parent_token,
      user: user,
      client: client
    } do
      child_token_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "urn:ietf:params:oauth:grant-type:token-exchange",
          "ref",
          token_family_id: parent_token.token_family_id,
          parent_token_id: parent_token.id
        )

      {:ok, child_token} = Repo.insert(child_token_changeset)

      assert child_token.token_family_id == parent_token.token_family_id
      assert child_token.parent_token_id == parent_token.id
    end

    test "create_for_user without parent creates new family_id", %{user: user, client: client} do
      token1_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "ref1"
        )

      token2_changeset =
        Token.create_for_user(
          user,
          client.client_id,
          ["api:write"],
          "authorization_code",
          "ref2"
        )

      {:ok, token1} = Repo.insert(token1_changeset)
      {:ok, token2} = Repo.insert(token2_changeset)

      # Each token should have its own family_id
      assert token1.token_family_id != token2.token_family_id
      assert is_nil(token1.parent_token_id)
      assert is_nil(token2.parent_token_id)
    end
  end
end
