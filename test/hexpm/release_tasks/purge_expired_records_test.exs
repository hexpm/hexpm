defmodule Hexpm.ReleaseTasks.PurgeExpiredRecordsTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.CronMonitor.SentryMock
  alias Hexpm.ReleaseTasks.PurgeExpiredRecords

  setup :verify_on_exit!

  test "runs as a monitored worker" do
    app_env(:hexpm, :sentry_impl, SentryMock)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts[:status] == :in_progress
      assert opts[:monitor_slug] == "hexpm-purge-expired-records"

      assert opts[:monitor_config] == [
               schedule: [type: :crontab, value: "0 2 * * *"],
               timezone: "Etc/UTC"
             ]

      {:ok, "check-in-id"}
    end)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               check_in_id: "check-in-id",
               status: :ok,
               monitor_slug: "hexpm-purge-expired-records"
             ]

      :ignored
    end)

    assert :ok = perform_job(PurgeExpiredRecords, %{})
  end

  test "rejects arguments because purging always processes all eligible records" do
    assert {:cancel, {:invalid_args, %{"date" => "2026-07-20"}}} =
             perform_job(PurgeExpiredRecords, %{"date" => "2026-07-20"})
  end

  defp seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end

  defp seconds_from_now(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  defp truncated_seconds_ago(seconds) do
    seconds_ago(seconds) |> DateTime.truncate(:second)
  end

  defp truncated_seconds_from_now(seconds) do
    seconds_from_now(seconds) |> DateTime.truncate(:second)
  end

  defp days_ago(days), do: seconds_ago(days * 86400)

  describe "purge authorization codes" do
    test "deletes any expired code" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
          code: "expired-code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          code_challenge: "challenge",
          code_challenge_method: "S256",
          user_id: user.id,
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
          code: "active-code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(600),
          code_challenge: "challenge2",
          code_challenge_method: "S256",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.AuthorizationCode, expired.id)
      assert Repo.get(Hexpm.OAuth.AuthorizationCode, active.id)
    end
  end

  describe "purge device codes" do
    test "deletes any expired code" do
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "expired-device",
          user_code: "EXPR1234",
          verification_uri: "https://hex.pm/device",
          expires_at: seconds_ago(60),
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "active-device",
          user_code: "ACTV5678",
          verification_uri: "https://hex.pm/device",
          expires_at: seconds_from_now(600),
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.DeviceCode, expired.id)
      assert Repo.get(Hexpm.OAuth.DeviceCode, active.id)
    end
  end

  describe "purge oauth tokens" do
    test "deletes any expired token" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "active-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, expired.id)
      assert Repo.get(Hexpm.OAuth.Token, active.id)
    end

    test "keeps expired tokens whose refresh token is still valid" do
      user = insert(:user)
      client = insert(:oauth_client)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-access-jti",
          refresh_jti: "live-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          refresh_token_expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.OAuth.Token, token.id)
    end

    test "deletes tokens whose refresh token has also expired" do
      user = insert(:user)
      client = insert(:oauth_client)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-access-jti",
          refresh_jti: "expired-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(86400),
          refresh_token_expires_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, token.id)
    end

    test "deletes any revoked token" do
      user = insert(:user)
      client = insert(:oauth_client)

      revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "revoked-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          revoked_at: truncated_seconds_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, revoked.id)
    end

    test "deletes revoked tokens whose refresh token has not expired" do
      user = insert(:user)
      client = insert(:oauth_client)

      revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "rotated-jti",
          refresh_jti: "rotated-refresh-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_ago(60),
          refresh_token_expires_at: truncated_seconds_from_now(86400),
          revoked_at: truncated_seconds_ago(60),
          grant_type: "refresh_token",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, revoked.id)
    end

    test "deletes records exceeding the batch size and keeps active ones" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        for i <- 1..5 do
          Repo.insert!(%Hexpm.OAuth.Token{
            jti: "expired-jti-#{i}",
            token_type: "bearer",
            scopes: ["api"],
            expires_at: truncated_seconds_ago(60),
            grant_type: "authorization_code",
            user_id: user.id,
            client_id: client.client_id
          })
        end

      active =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "active-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_seconds_from_now(86400),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run(batch_size: 2)
      PurgeExpiredRecords.run(batch_size: 2)

      for token <- expired do
        refute Repo.get(Hexpm.OAuth.Token, token.id)
      end

      assert Repo.get(Hexpm.OAuth.Token, active.id)
    end
  end

  describe "purge user sessions" do
    test "deletes any expired session" do
      user = insert(:user)

      expired =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "expired session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: seconds_ago(60),
          user_id: user.id
        })

      active =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "active session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: seconds_from_now(86400),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, expired.id)
      assert Repo.get(Hexpm.UserSession, active.id)
    end

    test "deletes any revoked session" do
      user = insert(:user)

      revoked =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "revoked session",
          session_token: :crypto.strong_rand_bytes(32),
          revoked_at: seconds_ago(60),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, revoked.id)
    end

    test "keeps sessions with no expiry or revocation" do
      user = insert(:user)

      active =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "active session",
          session_token: :crypto.strong_rand_bytes(32),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.UserSession, active.id)
    end
  end

  describe "purge password resets" do
    test "deletes resets older than 90 days" do
      user = insert(:user)

      old =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "old-key",
          primary_email: "old@example.com",
          user_id: user.id,
          inserted_at: days_ago(91)
        })

      recent =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "new-key",
          primary_email: "new@example.com",
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.PasswordReset, old.id)
      assert Repo.get(Hexpm.Accounts.PasswordReset, recent.id)
    end
  end

  describe "purge account deletion requests" do
    test "deletes requests older than 90 days" do
      user1 = insert(:user)
      user2 = insert(:user)

      old =
        Repo.insert!(%Hexpm.Accounts.AccountDeletionRequest{
          key: "old-key",
          primary_email: "old@example.com",
          user_id: user1.id,
          inserted_at: days_ago(91)
        })

      recent =
        Repo.insert!(%Hexpm.Accounts.AccountDeletionRequest{
          key: "new-key",
          primary_email: "new@example.com",
          user_id: user2.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.AccountDeletionRequest, old.id)
      assert Repo.get(Hexpm.Accounts.AccountDeletionRequest, recent.id)
    end
  end

  describe "purge keys" do
    test "deletes keys revoked more than 90 days ago" do
      user = insert(:user)

      revoked = insert(:key, user: user, revoke_at: days_ago(91))
      recent_revoked = insert(:key, user: user, revoke_at: days_ago(60))
      active = insert(:key, user: user)

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.Key, revoked.id)
      assert Repo.get(Hexpm.Accounts.Key, recent_revoked.id)
      assert Repo.get(Hexpm.Accounts.Key, active.id)
    end
  end

  describe "purge organization SSO transactions" do
    test "deletes expired transactions and retains active ones" do
      connection =
        insert(:organization_sso_connection,
          organization: insert(:organization)
        )

      expired =
        Repo.insert!(%Hexpm.Accounts.SSO.Transaction{
          connection_id: connection.id,
          state_hash: :crypto.hash(:sha256, "expired-state"),
          kind: "login",
          secret_slot: "active",
          connection_version: connection.version,
          secret_version: connection.version,
          redirect_uri: "https://hex.pm/sso/callback",
          expires_at: days_ago(1)
        })

      active =
        Repo.insert!(%Hexpm.Accounts.SSO.Transaction{
          connection_id: connection.id,
          state_hash: :crypto.hash(:sha256, "active-state"),
          kind: "login",
          secret_slot: "active",
          connection_version: connection.version,
          secret_version: connection.version,
          redirect_uri: "https://hex.pm/sso/callback",
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.Accounts.SSO.Transaction, expired.id)
      assert Repo.get(Hexpm.Accounts.SSO.Transaction, active.id)
    end
  end

  describe "purge organization SSO sessions" do
    test "deletes lapsed organization access sessions" do
      organization = insert(:organization)
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user)
      connection = insert(:organization_sso_connection, organization: organization)

      identity =
        insert(:organization_sso_identity,
          organization: organization,
          connection: connection,
          user: user
        )

      active = insert_org_session(organization, user, identity, expires_at: hours_from_now(1))
      expired = insert_org_session(organization, user, identity, expires_at: days_ago(1))

      # Revoked but not yet expired. The purge collects on expiry alone, so this
      # one has to survive; with `days_ago(1)` it was deleted for the same
      # reason `expired` was and covered nothing.
      revoked =
        insert_org_session(organization, user, identity,
          expires_at: hours_from_now(1),
          revoked_at: DateTime.utc_now()
        )

      PurgeExpiredRecords.run()

      assert Repo.get(Hexpm.Accounts.SSO.OrgSession, active.id)
      refute Repo.get(Hexpm.Accounts.SSO.OrgSession, expired.id)
      assert Repo.get(Hexpm.Accounts.SSO.OrgSession, revoked.id)
    end
  end

  defp insert_org_session(organization, user, identity, attrs) do
    {:ok, user_session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    Repo.insert!(%Hexpm.Accounts.SSO.OrgSession{
      user_id: user.id,
      organization_id: organization.id,
      user_session_id: user_session.id,
      identity_id: identity.id,
      authenticated_at: DateTime.utc_now(),
      expires_at: Keyword.fetch!(attrs, :expires_at),
      revoked_at: Keyword.get(attrs, :revoked_at)
    })
  end

  defp hours_from_now(hours), do: DateTime.add(DateTime.utc_now(), hours * 3600, :second)
end
