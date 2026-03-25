defmodule Hexpm.ReleaseTasks.PurgeExpiredRecordsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.ReleaseTasks.PurgeExpiredRecords

  defp days_ago(days) do
    DateTime.add(DateTime.utc_now(), -days * 86400, :second)
  end

  defp truncated_days_ago(days) do
    days_ago(days) |> DateTime.truncate(:second)
  end

  defp naive_days_ago(days) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-days * 86400, :second)
    |> NaiveDateTime.truncate(:second)
  end

  describe "purge authorization codes" do
    test "deletes expired codes older than 30 days" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.AuthorizationCode{
          code: "expired-code",
          redirect_uri: "https://example.com/callback",
          scopes: ["api"],
          expires_at: truncated_days_ago(31),
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
          expires_at:
            DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second),
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
    test "deletes expired codes older than 30 days" do
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "expired-device",
          user_code: "EXPR1234",
          verification_uri: "https://hex.pm/device",
          expires_at: days_ago(31),
          client_id: client.client_id
        })

      active =
        Repo.insert!(%Hexpm.OAuth.DeviceCode{
          device_code: "active-device",
          user_code: "ACTV5678",
          verification_uri: "https://hex.pm/device",
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second),
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.DeviceCode, expired.id)
      assert Repo.get(Hexpm.OAuth.DeviceCode, active.id)
    end
  end

  describe "purge password resets" do
    test "deletes resets older than 30 days" do
      user = insert(:user)

      old =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "old-key",
          primary_email: "old@example.com",
          user_id: user.id,
          inserted_at: days_ago(31)
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

  describe "purge oauth tokens" do
    test "deletes expired tokens older than 90 days" do
      user = insert(:user)
      client = insert(:oauth_client)

      expired =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "expired-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_days_ago(91),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      recent_expired =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "recent-expired-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_days_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, expired.id)
      assert Repo.get(Hexpm.OAuth.Token, recent_expired.id)
    end

    test "deletes revoked tokens older than 90 days" do
      user = insert(:user)
      client = insert(:oauth_client)

      revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "revoked-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at: truncated_days_ago(91),
          revoked_at: truncated_days_ago(91),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      recent_revoked =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "recent-revoked-jti",
          token_type: "bearer",
          scopes: ["api"],
          expires_at:
            DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          revoked_at: truncated_days_ago(60),
          grant_type: "authorization_code",
          user_id: user.id,
          client_id: client.client_id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.OAuth.Token, revoked.id)
      assert Repo.get(Hexpm.OAuth.Token, recent_revoked.id)
    end
  end

  describe "purge user sessions" do
    test "deletes expired sessions older than 90 days" do
      user = insert(:user)

      expired =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "expired session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: days_ago(91),
          user_id: user.id
        })

      recent =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "recent session",
          session_token: :crypto.strong_rand_bytes(32),
          expires_at: days_ago(60),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, expired.id)
      assert Repo.get(Hexpm.UserSession, recent.id)
    end

    test "deletes revoked sessions older than 90 days" do
      user = insert(:user)

      revoked =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "revoked session",
          session_token: :crypto.strong_rand_bytes(32),
          revoked_at: days_ago(91),
          user_id: user.id
        })

      recent_revoked =
        Repo.insert!(%Hexpm.UserSession{
          type: "browser",
          name: "recent revoked session",
          session_token: :crypto.strong_rand_bytes(32),
          revoked_at: days_ago(60),
          user_id: user.id
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.UserSession, revoked.id)
      assert Repo.get(Hexpm.UserSession, recent_revoked.id)
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

  describe "purge plug sessions" do
    test "deletes sessions inactive for more than 90 days" do
      stale =
        Repo.insert!(%Hexpm.PlugSession{
          token: :crypto.strong_rand_bytes(32),
          data: %{},
          inserted_at: naive_days_ago(91),
          updated_at: naive_days_ago(91)
        })

      recent =
        Repo.insert!(%Hexpm.PlugSession{
          token: :crypto.strong_rand_bytes(32),
          data: %{}
        })

      PurgeExpiredRecords.run()

      refute Repo.get(Hexpm.PlugSession, stale.id)
      assert Repo.get(Hexpm.PlugSession, recent.id)
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
end
