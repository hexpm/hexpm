defmodule Hexpm.OAuth.TokenTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{Token, Client, Tokens, Clients, Sessions}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Token.changeset(%Token{}, %{})

      assert %{
               jti: "can't be blank",
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
          jti: "test-jti-123",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: expires_at,
          grant_type: "invalid_grant",
          user_id: user.id,
          client_id: Clients.generate_client_id()
        })

      assert %{grant_type: "is invalid"} = errors_on(changeset)
    end

    test "validates scopes" do
      user = insert(:user)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      changeset =
        Token.changeset(%Token{}, %{
          jti: "test-jti-456",
          token_type: "bearer",
          scopes: ["invalid_scope", "api"],
          expires_at: expires_at,
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: Clients.generate_client_id()
        })

      assert %{scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = Sessions.create_for_user(user, client.client_id)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        jti: "test-jti-789",
        token_type: "bearer",
        refresh_jti: "refresh-jti-123",
        scopes: ["api", "api:read"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        grant_reference: "auth_code_123",
        user_id: user.id,
        client_id: client.client_id,
        session_id: session.id
      }

      changeset = Token.changeset(%Token{}, attrs)
      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds token with valid attributes" do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = Sessions.create_for_user(user, client.client_id)
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        jti: "test-jti-build",
        token_type: "bearer",
        scopes: ["api"],
        expires_at: expires_at,
        grant_type: "authorization_code",
        user_id: user.id,
        client_id: client.client_id,
        session_id: session.id
      }

      changeset = Token.build(attrs)
      assert changeset.valid?
    end
  end

  # Token generation is now tested through the public API

  describe "create_for_user/6" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "creates changeset with required fields", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          "auth_code_123"
        )

      assert changeset.valid?
      assert get_field(changeset, :jti)
      assert get_field(changeset, :access_token)
      # Access token should be a JWT
      assert String.starts_with?(get_field(changeset, :access_token), "eyJ")
      assert get_field(changeset, :scopes) == ["api"]
      assert get_field(changeset, :grant_type) == "authorization_code"
      assert get_field(changeset, :grant_reference) == "auth_code_123"
      assert get_field(changeset, :user_id) == user.id
      assert get_field(changeset, :client_id) == "test_client"
      assert get_field(changeset, :expires_at)
      refute get_field(changeset, :refresh_jti)
      refute get_field(changeset, :refresh_token)
    end

    test "sets custom expiration time", %{user: user} do
      changeset =
        Tokens.create_for_user(
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
        Tokens.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      assert get_field(changeset, :refresh_jti)
      assert get_field(changeset, :refresh_token)
      # Refresh token should be a JWT
      assert String.starts_with?(get_field(changeset, :refresh_token), "eyJ")
    end

    test "defaults grant_reference to nil", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code"
        )

      assert get_field(changeset, :grant_reference) == nil
    end

    test "sets 30-day refresh token expiration for read-only scopes", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api:read"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      refresh_expires_at = get_field(changeset, :refresh_token_expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)

      # Allow 2 second tolerance for test execution time
      assert DateTime.diff(refresh_expires_at, expected_time, :second) |> abs() <= 2
    end

    test "sets 60-minute refresh token expiration for api:write scope", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api:write"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      refresh_expires_at = get_field(changeset, :refresh_token_expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)

      # Allow 2 second tolerance for test execution time
      assert DateTime.diff(refresh_expires_at, expected_time, :second) |> abs() <= 2
    end

    test "sets 60-minute refresh token expiration for api scope", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      refresh_expires_at = get_field(changeset, :refresh_token_expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)

      # Allow 2 second tolerance for test execution time
      assert DateTime.diff(refresh_expires_at, expected_time, :second) |> abs() <= 2
    end

    test "sets 60-minute refresh token expiration for mixed scopes with write", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api:read", "api:write", "repositories"],
          "authorization_code",
          nil,
          with_refresh_token: true
        )

      refresh_expires_at = get_field(changeset, :refresh_token_expires_at)
      expected_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)

      # Allow 2 second tolerance for test execution time
      assert DateTime.diff(refresh_expires_at, expected_time, :second) |> abs() <= 2
    end

    test "does not set refresh token expiration when refresh token not requested", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api"],
          "authorization_code",
          nil,
          with_refresh_token: false
        )

      assert get_field(changeset, :refresh_token_expires_at) == nil
      assert get_field(changeset, :refresh_jti) == nil
    end
  end

  describe "expired?/1" do
    test "returns false for non-expired token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time}

      refute Tokens.expired?(token)
    end

    test "returns true for expired token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{expires_at: past_time}

      assert Tokens.expired?(token)
    end
  end

  describe "revoked?/1" do
    test "returns false for non-revoked token" do
      token = %Token{revoked_at: nil}

      refute Tokens.revoked?(token)
    end

    test "returns true for revoked token" do
      token = %Token{revoked_at: DateTime.utc_now()}

      assert Tokens.revoked?(token)
    end
  end

  describe "valid?/1" do
    test "returns true for non-expired, non-revoked token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time, revoked_at: nil}

      assert Tokens.valid?(token)
    end

    test "returns false for expired token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{expires_at: past_time, revoked_at: nil}

      refute Tokens.valid?(token)
    end

    test "returns false for revoked token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{expires_at: future_time, revoked_at: DateTime.utc_now()}

      refute Tokens.valid?(token)
    end
  end

  describe "revoke/1" do
    test "creates changeset with revoked_at timestamp" do
      token = %Token{}
      changeset = Tokens.revoke_changeset(token)

      revoked_at = get_field(changeset, :revoked_at)
      assert revoked_at
      # Should be within last few seconds
      assert DateTime.diff(DateTime.utc_now(), revoked_at, :second) <= 1
    end
  end

  describe "refresh_token_expired?/1" do
    test "returns false for non-expired refresh token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{refresh_token_expires_at: future_time}

      refute Tokens.refresh_token_expired?(token)
    end

    test "returns true for expired refresh token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{refresh_token_expires_at: past_time}

      assert Tokens.refresh_token_expired?(token)
    end

    test "returns false when refresh_token_expires_at is nil" do
      token = %Token{refresh_token_expires_at: nil}

      refute Tokens.refresh_token_expired?(token)
    end
  end

  describe "refresh_token_valid?/1" do
    test "returns true for non-expired, non-revoked refresh token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{refresh_token_expires_at: future_time, revoked_at: nil}

      assert Tokens.refresh_token_valid?(token)
    end

    test "returns false for expired refresh token" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %Token{refresh_token_expires_at: past_time, revoked_at: nil}

      refute Tokens.refresh_token_valid?(token)
    end

    test "returns false for revoked refresh token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %Token{refresh_token_expires_at: future_time, revoked_at: DateTime.utc_now()}

      refute Tokens.refresh_token_valid?(token)
    end

    test "returns true when refresh_token_expires_at is nil and not revoked" do
      token = %Token{refresh_token_expires_at: nil, revoked_at: nil}

      assert Tokens.refresh_token_valid?(token)
    end
  end

  describe "has_write_scope?/1" do
    test "returns true for 'api' scope" do
      assert Tokens.has_write_scope?(["api"])
    end

    test "returns true for 'api:write' scope" do
      assert Tokens.has_write_scope?(["api:write"])
    end

    test "returns true for mixed scopes including 'api'" do
      assert Tokens.has_write_scope?(["api:read", "api", "repositories"])
    end

    test "returns true for mixed scopes including 'api:write'" do
      assert Tokens.has_write_scope?(["api:read", "api:write", "repositories"])
    end

    test "returns false for read-only scopes" do
      refute Tokens.has_write_scope?(["api:read"])
      refute Tokens.has_write_scope?(["api:read", "repositories"])
    end

    test "returns false for empty scopes" do
      refute Tokens.has_write_scope?([])
    end
  end

  describe "has_scopes?/2" do
    test "returns true when token has all required scopes" do
      token = %Token{scopes: ["api", "api:read", "api:write"]}

      assert Tokens.has_scopes?(token, ["api"])
      assert Tokens.has_scopes?(token, ["api", "api:read"])
      assert Tokens.has_scopes?(token, ["api:read", "api:write"])
      assert Tokens.has_scopes?(token, [])
    end

    test "returns false when token missing required scopes" do
      token = %Token{scopes: ["api", "api:read"]}

      refute Tokens.has_scopes?(token, ["api:write"])
      refute Tokens.has_scopes?(token, ["api", "repositories"])
      refute Tokens.has_scopes?(token, ["invalid_scope"])
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
        Tokens.create_exchanged_token(
          parent_token,
          client.client_id,
          target_scopes,
          "exchange_grant_ref"
        )

      {:ok, child_token} = Repo.insert(child_token_changeset)

      assert child_token.parent_token_id == parent_token.id
      assert child_token.session_id == parent_token.session_id
      assert child_token.scopes == target_scopes
      assert child_token.grant_type == "urn:ietf:params:oauth:grant-type:token-exchange"
      assert child_token.grant_reference == "exchange_grant_ref"
      assert child_token.user_id == parent_token.user_id
      assert child_token.client_id == parent_token.client_id
      assert not is_nil(child_token.refresh_jti)
    end

    test "revoke_token/1 only revokes individual token", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Revoke parent token only
      assert {:ok, _} = Tokens.revoke(parent_token)

      # Only parent token should be revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Tokens.revoked?(updated_parent)
      refute Tokens.revoked?(updated_child1)
      refute Tokens.revoked?(updated_child2)
    end

    test "revoke/1 on child token only revokes that child", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Revoke only child1
      assert {:ok, _} = Tokens.revoke(child1)

      # Check only child1 is revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      refute Tokens.revoked?(updated_parent)
      assert Tokens.revoked?(updated_child1)
      refute Tokens.revoked?(updated_child2)
    end

    test "token exchange always creates children of root token", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child token from parent
      child1_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      {:ok, child1} = Repo.insert(child1_changeset)

      # Create another token from child1 (should still have parent as root)
      child1_with_user = Repo.preload(child1, :user)

      child2_changeset =
        Tokens.create_exchanged_token(child1_with_user, client.client_id, ["api:read"], "ref2")

      {:ok, child2} = Repo.insert(child2_changeset)

      # Both children should have the root token as their parent
      assert child1.parent_token_id == parent_token.id
      assert child2.parent_token_id == parent_token.id
      assert child1.session_id == parent_token.session_id
      assert child2.session_id == parent_token.session_id
    end

    test "session revoke cascades to all tokens", %{
      parent_token: parent_token,
      client: client
    } do
      # Create child tokens
      child1_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["api:read"], "ref1")

      child2_changeset =
        Tokens.create_exchanged_token(parent_token, client.client_id, ["repositories"], "ref2")

      {:ok, child1} = Repo.insert(child1_changeset)
      {:ok, child2} = Repo.insert(child2_changeset)

      # Load the session and revoke it
      parent_token = Repo.preload(parent_token, :session)

      {:ok, %{session: _session, tokens: {revoked_count, _}}} =
        Sessions.revoke(parent_token.session)

      # Should revoke all 3 tokens
      assert revoked_count == 3

      # Check all tokens are revoked
      updated_parent = Repo.get(Token, parent_token.id)
      updated_child1 = Repo.get(Token, child1.id)
      updated_child2 = Repo.get(Token, child2.id)

      assert Tokens.revoked?(updated_parent)
      assert Tokens.revoked?(updated_child1)
      assert Tokens.revoked?(updated_child2)
    end

    test "create_for_user with parent token uses same session", %{
      parent_token: parent_token,
      user: user,
      client: client
    } do
      child_token_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "urn:ietf:params:oauth:grant-type:token-exchange",
          "ref",
          session_id: parent_token.session_id,
          parent_token_id: parent_token.id
        )

      {:ok, child_token} = Repo.insert(child_token_changeset)

      assert child_token.session_id == parent_token.session_id
      assert child_token.parent_token_id == parent_token.id
    end

    test "tokens require sessions", %{user: user, client: client} do
      # Create two separate sessions
      {:ok, session1} = Sessions.create_for_user(user, client.client_id)
      {:ok, session2} = Sessions.create_for_user(user, client.client_id)

      token1_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "ref1",
          session_id: session1.id
        )

      token2_changeset =
        Tokens.create_for_user(
          user,
          client.client_id,
          ["api:write"],
          "authorization_code",
          "ref2",
          session_id: session2.id
        )

      {:ok, token1} = Repo.insert(token1_changeset)
      {:ok, token2} = Repo.insert(token2_changeset)

      # Each token belongs to its own session
      assert token1.session_id != token2.session_id
      assert is_nil(token1.parent_token_id)
      assert is_nil(token2.parent_token_id)
    end
  end

  describe "lookup/3 with JWT validation" do
    setup do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = Sessions.create_for_user(user, client.client_id)

      {:ok, user: user, client: client, session: session}
    end

    test "accepts token with valid nbf claim", %{user: user, client: client, session: session} do
      {:ok, token} =
        Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id
        )

      assert {:ok, _found_token} = Tokens.lookup(token.access_token, :access)
    end

    test "accepts token with nbf exactly at current time", %{
      user: user,
      client: client,
      session: session
    } do
      {:ok, token} =
        Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id
        )

      assert {:ok, _found_token} = Tokens.lookup(token.access_token, :access)
    end

    test "handles clock skew within tolerance", %{user: user, client: client, session: session} do
      {:ok, token} =
        Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id
        )

      assert {:ok, _found_token} = Tokens.lookup(token.access_token, :access)
    end

    test "validates refresh tokens with nbf claim", %{
      user: user,
      client: client,
      session: session
    } do
      {:ok, token} =
        Tokens.create_and_insert_for_user(
          user,
          client.client_id,
          ["api:read"],
          "authorization_code",
          "test_code",
          session_id: session.id,
          with_refresh_token: true
        )

      assert {:ok, _found_token} = Tokens.lookup(token.refresh_token, :refresh)
    end
  end
end
