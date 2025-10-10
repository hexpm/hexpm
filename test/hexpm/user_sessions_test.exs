defmodule Hexpm.UserSessionsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.UserSessions

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
          session_token = :crypto.strong_rand_bytes(96)

          attrs = %{
            user_id: user.id,
            type: "browser",
            name: "Session #{i}",
            session_token: session_token
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
end
