defmodule Hexpm.ReleaseTasks.PurgeExpiredRecordsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.ReleaseTasks.PurgeExpiredRecords

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

  defp naive_days_ago(days) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-days * 86400, :second)
    |> NaiveDateTime.truncate(:second)
  end

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

  describe "purge plug sessions" do
    test "deletes sessions inactive for more than 30 days" do
      stale =
        Repo.insert!(%Hexpm.PlugSession{
          token: :crypto.strong_rand_bytes(32),
          data: %{},
          inserted_at: naive_days_ago(31),
          updated_at: naive_days_ago(31)
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
