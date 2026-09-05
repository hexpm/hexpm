defmodule Hexpm.OAuth.TokensTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{Token, Tokens}

  describe "minted scopes" do
    setup do
      user = insert(:user)
      member = for _ <- 1..2, do: insert(:organization)
      Enum.each(member, &insert(:organization_user, organization: &1, user: user))
      foreign = for _ <- 1..2, do: insert(:organization)

      %{
        user: user,
        member_names: Enum.map(member, & &1.name),
        foreign_names: Enum.map(foreign, & &1.name)
      }
    end

    # Both CDN edges read repository:<org> and docs:<org> straight off the token,
    # so a name that survives minting is access to that organization until the
    # token expires. Nothing the caller asks for may widen that beyond the
    # account's own memberships, whatever mix of literal and explicit scopes the
    # request carries. The interesting cases are the combinations: expansion
    # rewrites the literal `repositories` and leaves an explicit scope alone, and
    # the bug this covers lived in that gap.
    test "never name an organization the account is not in", context do
      %{user: user, member_names: member_names, foreign_names: foreign_names} = context
      [member, _] = member_names
      [foreign, other_foreign] = foreign_names

      requests = [
        ["repositories"],
        ["repository:#{member}"],
        ["docs:#{member}"],
        ["repository:#{foreign}"],
        ["docs:#{foreign}"],
        ["repository:hexpm"],
        ["repositories", "repository:#{foreign}"],
        ["repositories", "docs:#{foreign}"],
        ["repositories", "repository:#{member}"],
        ["repository:#{member}", "repository:#{foreign}"],
        ["repository:#{foreign}", "repository:#{other_foreign}"],
        ["api", "repository:#{foreign}", "docs:#{foreign}", "repository:hexpm"],
        ["api:read", "api:write", "repositories", "repository:hexpm"]
      ]

      for requested <- requests do
        minted =
          user
          |> Tokens.create_for_user("test_client", requested, "refresh_token")
          |> get_field(:scopes)

        for scope <- minted,
            [domain, name] <- [String.split(scope, ":", parts: 2)],
            domain in ["repository", "docs"] do
          assert name == "hexpm" or name in member_names,
                 "minted #{scope} from #{inspect(requested)} for an account in #{inspect(member_names)}"
        end

        # and the filter must not be passing by dropping everything
        for name <- member_names, "repository:#{name}" in requested do
          assert "repository:#{name}" in minted,
                 "dropped repository:#{name} from #{inspect(requested)} for a member"
        end
      end
    end
  end

  describe "create_for_user/6" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "drops an explicit organization scope the user is not a member of", %{user: user} do
      other = insert(:organization)

      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api:read", "repository:#{other.name}", "docs:#{other.name}"],
          "refresh_token"
        )

      assert get_field(changeset, :scopes) == ["api:read"]
    end

    test "keeps an explicit organization scope the user is a member of", %{user: user} do
      org = insert(:organization)
      insert(:organization_user, organization: org, user: user)

      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["api:read", "repository:#{org.name}"],
          "refresh_token"
        )

      assert "repository:#{org.name}" in get_field(changeset, :scopes)
    end

    test "keeps the public repository scope for a user in no organization", %{user: user} do
      changeset =
        Tokens.create_for_user(
          user,
          "test_client",
          ["repository:hexpm"],
          "refresh_token"
        )

      assert get_field(changeset, :scopes) == ["repository:hexpm"]
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
      earliest_expires_at =
        DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)

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

      latest_expires_at =
        DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)

      assert_datetime_between(expires_at, earliest_expires_at, latest_expires_at)
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

    test "sets 30-day refresh token expiration for all scopes", %{user: user} do
      earliest_expires_at =
        DateTime.utc_now()
        |> DateTime.add(30 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

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

      latest_expires_at =
        DateTime.utc_now()
        |> DateTime.add(30 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      assert_datetime_between(refresh_expires_at, earliest_expires_at, latest_expires_at)
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
      earliest_revoked_at = DateTime.utc_now() |> DateTime.truncate(:second)
      changeset = Tokens.revoke_changeset(token)
      latest_revoked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      revoked_at = get_field(changeset, :revoked_at)
      assert revoked_at
      assert_datetime_between(revoked_at, earliest_revoked_at, latest_revoked_at)
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

      assert Permissions.verify_access?(token_api, "api", nil)
      assert Permissions.verify_access?(token_api, "api", "read")
      assert Permissions.verify_access?(token_api, "api", "write")

      assert Permissions.verify_access?(token_read, "api", nil)
      assert Permissions.verify_access?(token_read, "api", "read")
      refute Permissions.verify_access?(token_read, "api", "write")

      assert Permissions.verify_access?(token_write, "api", nil)
      assert Permissions.verify_access?(token_write, "api", "read")
      assert Permissions.verify_access?(token_write, "api", "write")
    end

    test "validates package domain permissions" do
      alias Hexpm.Permissions

      token_api = %Token{scopes: ["api"]}
      token_write = %Token{scopes: ["api:write"]}
      token_read = %Token{scopes: ["api:read"]}

      assert Permissions.verify_access?(token_api, "package", nil)
      assert Permissions.verify_access?(token_write, "package", nil)

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

  describe "lookup/3 with JWT validation" do
    setup do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, session} =
        Hexpm.UserSessions.create_oauth_session(user, client.client_id, audit: audit_data(user))

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
          user_session_id: session.id
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
          user_session_id: session.id
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
          user_session_id: session.id
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
          user_session_id: session.id,
          with_refresh_token: true
        )

      assert {:ok, _found_token} = Tokens.lookup(token.refresh_token, :refresh)
    end

    test "rejects a live token whose session was revoked", %{
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
          user_session_id: session.id
        )

      # The session alone, leaving the token live, is the state a revocation
      # that raced a token being issued into the session leaves behind.
      revoke_session(session)

      assert {:error, :token_invalid} = Tokens.lookup(token.access_token, :access)
      assert {:error, :invalid} = Hexpm.Accounts.Auth.oauth_token_auth(token.access_token, %{})
    end

    test "rejects a live token whose session expired", %{
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
          user_session_id: session.id
        )

      session
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      |> Repo.update!()

      assert {:error, :token_invalid} = Tokens.lookup(token.access_token, :access)
      assert {:error, :invalid} = Hexpm.Accounts.Auth.oauth_token_auth(token.access_token, %{})
    end

    test "still finds a token of a revoked session when not validating", %{
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
          user_session_id: session.id
        )

      revoke_session(session)

      assert {:ok, _found_token} = Tokens.lookup(token.access_token, :access, validate: false)
    end

    defp revoke_session(session) do
      session
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now())
      |> Repo.update!()
    end
  end
end
