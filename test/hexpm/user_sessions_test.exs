defmodule Hexpm.UserSessionsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.UserSessions
  alias Hexpm.Accounts.{AuditLog, AuditLogs}

  describe "session limit enforcement" do
    test "limits browser sessions to 5 per user" do
      user = insert(:user)

      # Create 5 browser sessions
      sessions =
        for i <- 1..5 do
          {:ok, session, _token} =
            UserSessions.create_browser_session(user, name: "Session #{i}")

          session
        end

      # Verify we have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Create a 6th session
      {:ok, _new_session, _token} =
        UserSessions.create_browser_session(user, name: "Session 6")

      # Verify we still only have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Verify the oldest session (first one) was revoked
      first_session = Repo.get(Hexpm.UserSession, List.first(sessions).id)
      assert first_session.revoked_at != nil
    end

    test "limits OAuth sessions to 5 per user" do
      user = insert(:user)
      client = insert(:oauth_client)

      # Create 5 OAuth sessions
      sessions =
        for i <- 1..5 do
          {:ok, session} =
            UserSessions.create_oauth_session(user, client.client_id, name: "OAuth #{i}")

          session
        end

      # Verify we have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Create a 6th session
      {:ok, _new_session} =
        UserSessions.create_oauth_session(user, client.client_id, name: "OAuth 6")

      # Verify we still only have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Verify the oldest session was revoked
      first_session = Repo.get(Hexpm.UserSession, List.first(sessions).id)
      assert first_session.revoked_at != nil
    end

    test "limits combined browser and OAuth sessions to 5" do
      user = insert(:user)
      client = insert(:oauth_client)

      # Create 3 browser sessions
      browser_sessions =
        for i <- 1..3 do
          {:ok, session, _token} =
            UserSessions.create_browser_session(user, name: "Browser #{i}")

          session
        end

      # Create 2 OAuth sessions
      oauth_sessions =
        for i <- 1..2 do
          {:ok, session} =
            UserSessions.create_oauth_session(user, client.client_id, name: "OAuth #{i}")

          session
        end

      # Verify we have 5 sessions total
      assert UserSessions.count_for_user(user) == 5

      # Create another browser session (6th total)
      {:ok, _new_session, _token} =
        UserSessions.create_browser_session(user, name: "Browser 4")

      # Verify we still only have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Verify the oldest session (first browser session) was revoked
      first_session = Repo.get(Hexpm.UserSession, List.first(browser_sessions).id)
      assert first_session.revoked_at != nil

      # Verify OAuth sessions are still active
      Enum.each(oauth_sessions, fn session ->
        reloaded = Repo.get(Hexpm.UserSession, session.id)
        assert reloaded.revoked_at == nil
      end)
    end

    test "revokes least recently used session based on last_use" do
      user = insert(:user)

      # Create 5 sessions
      sessions =
        for i <- 1..5 do
          {:ok, session, _token} =
            UserSessions.create_browser_session(user, name: "Session #{i}")

          session
        end

      # Update last_use on all sessions with different timestamps
      now = DateTime.utc_now()

      Enum.with_index(sessions, fn session, index ->
        # Session at index 2 (3rd session) will be oldest when used
        used_at = DateTime.add(now, -(5 - index) * 60, :second)

        {:ok, _} =
          UserSessions.update_last_use(session, %{
            used_at: used_at,
            ip: "127.0.0.1",
            user_agent: "Test"
          })
      end)

      # Create a 6th session
      {:ok, _new_session, _token} =
        UserSessions.create_browser_session(user, name: "Session 6")

      # Verify we still only have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Verify the least recently used session (first in the list, oldest usage) was revoked
      first_session = Repo.get(Hexpm.UserSession, List.first(sessions).id)
      assert first_session.revoked_at != nil
    end

    test "revokes sessions without last_use first (never used)" do
      user = insert(:user)

      # Create 5 sessions
      sessions =
        for i <- 1..5 do
          {:ok, session, _token} =
            UserSessions.create_browser_session(user, name: "Session #{i}")

          session
        end

      # Update last_use on sessions 2-5, but not session 1
      now = DateTime.utc_now()

      sessions
      |> Enum.drop(1)
      |> Enum.with_index(fn session, index ->
        used_at = DateTime.add(now, -index * 60, :second)

        {:ok, _} =
          UserSessions.update_last_use(session, %{
            used_at: used_at,
            ip: "127.0.0.1",
            user_agent: "Test"
          })
      end)

      # Create a 6th session
      {:ok, _new_session, _token} =
        UserSessions.create_browser_session(user, name: "Session 6")

      # Verify we still only have 5 sessions
      assert UserSessions.count_for_user(user) == 5

      # Verify the session without last_use (first session) was revoked
      first_session = Repo.get(Hexpm.UserSession, List.first(sessions).id)
      assert first_session.revoked_at != nil

      # Verify sessions with last_use are still active
      sessions
      |> Enum.drop(1)
      |> Enum.each(fn session ->
        reloaded = Repo.get(Hexpm.UserSession, session.id)
        assert reloaded.revoked_at == nil
      end)
    end

    test "handles multiple sessions exceeding the limit" do
      user = insert(:user)

      # Create 7 sessions (shouldn't happen in practice, but test edge case)
      # We'll create them directly without enforcement to simulate a race condition
      sessions =
        for i <- 1..7 do
          session_token = :crypto.strong_rand_bytes(32)
          expires_at = DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)

          attrs = %{
            user_id: user.id,
            type: "browser",
            name: "Session #{i}",
            session_token: session_token,
            expires_at: expires_at
          }

          changeset = Hexpm.UserSession.changeset(%Hexpm.UserSession{}, attrs)
          {:ok, session} = Repo.insert(changeset)
          session
        end

      # Verify we have 7 sessions (bypassed enforcement)
      assert UserSessions.count_for_user(user) == 7

      # Now try to create another session with enforcement
      {:ok, _new_session, _token} =
        UserSessions.create_browser_session(user, name: "Session 8")

      # Verify we now have only 5 sessions (should have revoked 3 oldest: 7 - 4 = 3)
      assert UserSessions.count_for_user(user) == 5

      # Verify the 3 oldest sessions were revoked
      Enum.take(sessions, 3)
      |> Enum.each(fn session ->
        reloaded = Repo.get(Hexpm.UserSession, session.id)
        assert reloaded.revoked_at != nil
      end)
    end
  end

  describe "session expiration" do
    test "browser sessions are created with 30-day expiration" do
      user = insert(:user)

      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test Session")

      expected_expires_at = DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)
      assert DateTime.diff(session.expires_at, expected_expires_at, :second) |> abs() <= 2
    end

    test "OAuth sessions are created with 30-day expiration" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, session} = UserSessions.create_oauth_session(user, client.client_id, name: "Test")

      expected_expires_at = DateTime.add(DateTime.utc_now(), 30 * 24 * 60 * 60, :second)
      assert DateTime.diff(session.expires_at, expected_expires_at, :second) |> abs() <= 2
    end

    test "get_browser_session_by_token returns nil for expired session" do
      user = insert(:user)
      {:ok, session, token} = UserSessions.create_browser_session(user, name: "Test")

      # Manually expire the session
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))

      # Try to look up the expired session
      assert UserSessions.get_browser_session_by_token(token) == nil
    end

    test "all_for_user excludes expired sessions" do
      user = insert(:user)

      # Create 3 active sessions
      for i <- 1..3 do
        UserSessions.create_browser_session(user, name: "Active #{i}")
      end

      # Create 2 expired sessions
      for i <- 1..2 do
        {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Expired #{i}")
        past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
        Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))
      end

      # Should only return active sessions
      active_sessions = UserSessions.all_for_user(user)
      assert length(active_sessions) == 3
    end

    test "count_for_user doesn't count expired sessions" do
      user = insert(:user)

      # Create 3 active sessions
      for i <- 1..3 do
        UserSessions.create_browser_session(user, name: "Active #{i}")
      end

      # Create 2 expired sessions
      for i <- 1..2 do
        {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Expired #{i}")
        past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
        Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))
      end

      # Should only count active sessions
      assert UserSessions.count_for_user(user) == 3
    end

    test "expired sessions don't count toward session limit" do
      user = insert(:user)

      # Create 5 active sessions
      sessions =
        for i <- 1..5 do
          {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Session #{i}")
          session
        end

      # Expire 2 of them
      Enum.take(sessions, 2)
      |> Enum.each(fn session ->
        past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
        Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))
      end)

      # Should be able to create 3 more (only 3 active, limit is 5)
      {:ok, _s1, _} = UserSessions.create_browser_session(user, name: "New 1")
      {:ok, _s2, _} = UserSessions.create_browser_session(user, name: "New 2")
      {:ok, _s3, _} = UserSessions.create_browser_session(user, name: "New 3")

      # Should have 5 active sessions now (expired ones don't count)
      assert UserSessions.count_for_user(user) == 5
    end

    test "expired?/1 returns false for non-expired session" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      refute Hexpm.UserSession.expired?(session)
    end

    test "expired?/1 returns true for expired session" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      # Manually expire the session
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      expired_session =
        Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))

      assert Hexpm.UserSession.expired?(expired_session)
    end

    test "expired?/1 returns false when expires_at is nil" do
      session = %Hexpm.UserSession{expires_at: nil}
      refute Hexpm.UserSession.expired?(session)
    end

    test "active?/1 returns true for non-expired, non-revoked session" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      assert Hexpm.UserSession.active?(session)
    end

    test "active?/1 returns false for expired session" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      expired_session =
        Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))

      refute Hexpm.UserSession.active?(expired_session)
    end

    test "active?/1 returns false for revoked session" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      {:ok, revoked_session} = UserSessions.revoke(session)

      refute Hexpm.UserSession.active?(revoked_session)
    end

    test "cleanup_expired_sessions deletes expired sessions" do
      user = insert(:user)

      # Create 3 active sessions
      for i <- 1..3 do
        UserSessions.create_browser_session(user, name: "Active #{i}")
      end

      # Create 2 expired sessions
      expired_ids =
        for i <- 1..2 do
          {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Expired #{i}")
          past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
          Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))
          session.id
        end

      # Run cleanup
      {deleted_count, _} = UserSessions.cleanup_expired_sessions()
      assert deleted_count == 2

      # Verify expired sessions were deleted
      Enum.each(expired_ids, fn id ->
        assert Repo.get(Hexpm.UserSession, id) == nil
      end)

      # Verify active sessions still exist
      assert UserSessions.count_for_user(user) == 3
    end
  end

  describe "OAuth token expiration" do
    test "OAuth token inherits session expires_at" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, token} =
        Hexpm.OAuth.Tokens.create_session_and_token_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true
        )

      token = Repo.preload(token, :user_session)

      # Compare truncated to seconds (JWT doesn't preserve microseconds)
      token_expires = DateTime.truncate(token.refresh_token_expires_at, :second)
      session_expires = DateTime.truncate(token.user_session.expires_at, :second)

      assert token_expires == session_expires
    end

    test "token refresh preserves expires_at (no sliding window)" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, token} =
        Hexpm.OAuth.Tokens.create_session_and_token_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true
        )

      original_expires_at = token.refresh_token_expires_at

      # Preload user for revoke_and_create_token
      token = Repo.preload(token, :user)

      # Wait a moment
      :timer.sleep(10)

      # Refresh the token
      {:ok, new_token} =
        Hexpm.OAuth.Tokens.revoke_and_create_token(
          token,
          client.client_id,
          ["api"],
          "refresh_token",
          token.refresh_token,
          with_refresh_token: true,
          user_session_id: token.user_session_id
        )

      # Should have the same expiration (not extended)
      assert new_token.refresh_token_expires_at == original_expires_at
    end

    test "token refresh doesn't extend session expiration" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, token} =
        Hexpm.OAuth.Tokens.create_session_and_token_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true
        )

      session = Repo.get(Hexpm.UserSession, token.user_session_id)
      original_expires_at = session.expires_at

      # Preload user for revoke_and_create_token
      token = Repo.preload(token, :user)

      # Wait a moment
      :timer.sleep(10)

      # Refresh the token
      {:ok, _new_token} =
        Hexpm.OAuth.Tokens.revoke_and_create_token(
          token,
          client.client_id,
          ["api"],
          "refresh_token",
          token.refresh_token,
          with_refresh_token: true,
          user_session_id: token.user_session_id
        )

      # Reload session and verify expiration unchanged
      reloaded_session = Repo.get(Hexpm.UserSession, token.user_session_id)
      assert reloaded_session.expires_at == original_expires_at
    end
  end

  describe "session revocation" do
    test "revoke/1 for browser session sets revoked_at" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      {:ok, revoked_session} = UserSessions.revoke(session)

      assert revoked_session.revoked_at != nil
      assert DateTime.diff(DateTime.utc_now(), revoked_session.revoked_at, :second) <= 1
    end

    test "revoke/1 for OAuth session sets revoked_at" do
      user = insert(:user)
      client = insert(:oauth_client)
      {:ok, session} = UserSessions.create_oauth_session(user, client.client_id, name: "Test")

      {:ok, %{session: revoked_session, tokens: _}} = UserSessions.revoke(session)

      assert revoked_session.revoked_at != nil
      assert DateTime.diff(DateTime.utc_now(), revoked_session.revoked_at, :second) <= 1
    end

    test "revoke/1 for OAuth session also revokes all associated tokens" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, token} =
        Hexpm.OAuth.Tokens.create_session_and_token_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true
        )

      session = Repo.get(Hexpm.UserSession, token.user_session_id)

      {:ok, %{session: _revoked_session, tokens: {token_count, nil}}} =
        UserSessions.revoke(session)

      # Should have revoked 1 token
      assert token_count == 1

      # Verify token was actually revoked
      reloaded_token = Repo.get(Hexpm.OAuth.Token, token.id)
      assert reloaded_token.revoked_at != nil
    end

    test "revoked sessions are excluded from all_for_user" do
      user = insert(:user)

      # Create 2 active sessions
      UserSessions.create_browser_session(user, name: "Active 1")
      UserSessions.create_browser_session(user, name: "Active 2")

      # Create and revoke 1 session
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Revoked")
      UserSessions.revoke(session)

      # Should only return active sessions
      active_sessions = UserSessions.all_for_user(user)
      assert length(active_sessions) == 2
    end

    test "revoked sessions are excluded from count_for_user" do
      user = insert(:user)

      # Create 2 active sessions
      UserSessions.create_browser_session(user, name: "Active 1")
      UserSessions.create_browser_session(user, name: "Active 2")

      # Create and revoke 1 session
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Revoked")
      UserSessions.revoke(session)

      # Should only count active sessions
      assert UserSessions.count_for_user(user) == 2
    end

    test "get_browser_session_by_token returns nil for revoked session" do
      user = insert(:user)
      {:ok, session, token} = UserSessions.create_browser_session(user, name: "Test")

      UserSessions.revoke(session)

      # Should not return revoked session
      assert UserSessions.get_browser_session_by_token(token) == nil
    end
  end

  describe "last use tracking" do
    test "update_last_use/2 updates last_use embedded field" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      usage_info = %{
        used_at: DateTime.utc_now(),
        ip: "192.168.1.1",
        user_agent: "Mozilla/5.0"
      }

      {:ok, updated_session} = UserSessions.update_last_use(session, usage_info)

      assert updated_session.last_use != nil
    end

    test "update_last_use/2 stores IP address" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      usage_info = %{
        used_at: DateTime.utc_now(),
        ip: "192.168.1.1",
        user_agent: "Mozilla/5.0"
      }

      {:ok, updated_session} = UserSessions.update_last_use(session, usage_info)

      assert updated_session.last_use.ip == "192.168.1.1"
    end

    test "update_last_use/2 stores user agent" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      usage_info = %{
        used_at: DateTime.utc_now(),
        ip: "192.168.1.1",
        user_agent: "Mozilla/5.0"
      }

      {:ok, updated_session} = UserSessions.update_last_use(session, usage_info)

      assert updated_session.last_use.user_agent == "Mozilla/5.0"
    end

    test "update_last_use/2 stores used_at timestamp" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      used_at = DateTime.utc_now()

      usage_info = %{
        used_at: used_at,
        ip: "192.168.1.1",
        user_agent: "Mozilla/5.0"
      }

      {:ok, updated_session} = UserSessions.update_last_use(session, usage_info)

      assert DateTime.diff(updated_session.last_use.used_at, used_at, :second) == 0
    end
  end

  describe "audit logging" do
    test "create_browser_session logs session.create audit event" do
      user = insert(:user)

      {:ok, session, _token} =
        UserSessions.create_browser_session(user,
          name: "Test Browser",
          audit: audit_data(user)
        )

      assert [%AuditLog{action: "session.create"}] = AuditLogs.all_by(user)

      # Verify audit log params contain session info
      [log] = AuditLogs.all_by(user)
      assert log.params["id"] == session.id
      assert log.params["type"] == "browser"
      assert log.params["name"] == "Test Browser"
      assert log.user_id == user.id
    end

    test "create_oauth_session logs session.create audit event" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, session} =
        UserSessions.create_oauth_session(user, client.client_id,
          name: "CLI",
          audit: audit_data(user)
        )

      assert [%AuditLog{action: "session.create"}] = AuditLogs.all_by(user)

      # Verify audit log params contain session and client info
      [log] = AuditLogs.all_by(user)
      assert log.params["id"] == session.id
      assert log.params["type"] == "oauth"
      assert log.params["name"] == "CLI"
      assert log.params["client_id"] == client.client_id
      assert log.params["client"]["name"] == client.name
    end

    test "revoke/1 for browser session logs session.revoke audit event" do
      user = insert(:user)

      {:ok, session, _token} =
        UserSessions.create_browser_session(user,
          name: "Test",
          audit: audit_data(user)
        )

      {:ok, _} = UserSessions.revoke(session, nil, audit: audit_data(user))

      # Should have 2 audit logs: create + revoke
      assert [
               %AuditLog{action: "session.revoke"},
               %AuditLog{action: "session.create"}
             ] = AuditLogs.all_by(user)

      [revoke_log | _] = AuditLogs.all_by(user)
      assert revoke_log.params["id"] == session.id
      assert revoke_log.params["type"] == "browser"
    end

    test "revoke/1 for OAuth session logs session.revoke audit event" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, session} =
        UserSessions.create_oauth_session(user, client.client_id,
          name: "CLI",
          audit: audit_data(user)
        )

      {:ok, _} = UserSessions.revoke(session, nil, audit: audit_data(user))

      # Should have 2 audit logs: create + revoke
      assert [
               %AuditLog{action: "session.revoke"},
               %AuditLog{action: "session.create"}
             ] = AuditLogs.all_by(user)

      [revoke_log | _] = AuditLogs.all_by(user)
      assert revoke_log.params["id"] == session.id
      assert revoke_log.params["type"] == "oauth"
      assert revoke_log.params["client"]["name"] == client.name
    end

    test "create_browser_session without audit option does not create audit log" do
      user = insert(:user)

      {:ok, _session, _token} = UserSessions.create_browser_session(user, name: "Test")

      assert [] = AuditLogs.all_by(user)
    end

    test "create_oauth_session without audit option does not create audit log" do
      user = insert(:user)
      client = insert(:oauth_client)

      {:ok, _session} = UserSessions.create_oauth_session(user, client.client_id, name: "Test")

      assert [] = AuditLogs.all_by(user)
    end

    test "revoke/1 without audit option does not create audit log" do
      user = insert(:user)
      {:ok, session, _token} = UserSessions.create_browser_session(user, name: "Test")

      {:ok, _} = UserSessions.revoke(session)

      assert [] = AuditLogs.all_by(user)
    end

    test "audit log contains user information" do
      user = insert(:user)

      {:ok, _session, _token} =
        UserSessions.create_browser_session(user,
          name: "Test",
          audit: audit_data(user)
        )

      [log] = AuditLogs.all_by(user)
      assert log.user_id == user.id
      assert log.user_agent == "TEST"
      assert log.remote_ip == "127.0.0.1"
    end
  end
end
