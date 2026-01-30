defmodule HexpmWeb.Dashboard.SessionControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.UserSessions

  setup do
    user = insert(:user)
    conn = test_login(build_conn(), user)
    %{conn: conn, user: user}
  end

  describe "GET /dashboard/sessions" do
    test "shows all active sessions", %{conn: conn, user: user} do
      # Create additional sessions
      UserSessions.create_browser_session(user, name: "Firefox", audit: test_audit_data(user))

      {:ok, _} =
        UserSessions.create_oauth_session(user, insert(:oauth_client).client_id,
          name: "CLI",
          audit: test_audit_data(user)
        )

      conn = get(conn, ~p"/dashboard/sessions")

      assert html_response(conn, 200)
      # Should show at least 3 sessions (current + firefox + CLI)
      assert conn.resp_body =~ "Firefox"
      assert conn.resp_body =~ "CLI"
    end

    test "excludes expired sessions", %{conn: conn, user: user} do
      # Create an expired session
      {:ok, session, _token} =
        UserSessions.create_browser_session(user,
          name: "Expired Session",
          audit: test_audit_data(user)
        )

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))

      conn = get(conn, ~p"/dashboard/sessions")

      assert html_response(conn, 200)
      refute conn.resp_body =~ "Expired Session"
    end

    test "shows both browser and OAuth sessions", %{conn: conn, user: user} do
      UserSessions.create_browser_session(user, name: "Chrome", audit: test_audit_data(user))

      {:ok, _} =
        UserSessions.create_oauth_session(user, insert(:oauth_client).client_id,
          name: "Hex CLI",
          audit: test_audit_data(user)
        )

      conn = get(conn, ~p"/dashboard/sessions")

      assert html_response(conn, 200)
      assert conn.resp_body =~ "Chrome"
      assert conn.resp_body =~ "Hex CLI"
    end
  end

  describe "DELETE /dashboard/sessions/:id" do
    test "successfully revokes browser session", %{conn: conn, user: user} do
      {:ok, session, _token} =
        UserSessions.create_browser_session(user, name: "To Delete", audit: test_audit_data(user))

      conn = delete(conn, ~p"/dashboard/sessions?id=#{session.id}")

      assert redirected_to(conn) == ~p"/dashboard/sessions"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "browser session was revoked"

      # Verify session was revoked
      reloaded = Repo.get(Hexpm.UserSession, session.id)
      assert reloaded.revoked_at != nil
    end

    test "successfully revokes OAuth session", %{conn: conn, user: user} do
      client = insert(:oauth_client)

      {:ok, session} =
        UserSessions.create_oauth_session(user, client.client_id,
          name: "OAuth To Delete",
          audit: test_audit_data(user)
        )

      conn = delete(conn, ~p"/dashboard/sessions?id=#{session.id}")

      assert redirected_to(conn) == ~p"/dashboard/sessions"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "OAuth session was revoked"

      # Verify session was revoked
      reloaded = Repo.get(Hexpm.UserSession, session.id)
      assert reloaded.revoked_at != nil
    end

    test "revokes OAuth session's tokens", %{conn: conn, user: user} do
      client = insert(:oauth_client)

      {:ok, token} =
        Hexpm.OAuth.Tokens.create_session_and_token_for_user(
          user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true,
          audit: test_audit_data(user)
        )

      session = Repo.get(Hexpm.UserSession, token.user_session_id)

      conn = delete(conn, ~p"/dashboard/sessions?id=#{session.id}")

      assert redirected_to(conn) == ~p"/dashboard/sessions"

      # Verify token was revoked
      reloaded_token = Repo.get(Hexpm.OAuth.Token, token.id)
      assert reloaded_token.revoked_at != nil
    end

    test "prevents revoking current browser session", %{conn: conn, user: _user} do
      # Get the current session ID from the conn
      session_token = get_session(conn, "session_token")
      {:ok, decoded_token} = Base.decode64(session_token)
      current_session = UserSessions.get_browser_session_by_token(decoded_token)

      conn = delete(conn, ~p"/dashboard/sessions?id=#{current_session.id}")

      assert redirected_to(conn) == ~p"/dashboard/sessions"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Cannot revoke your current session"

      # Verify session was NOT revoked
      reloaded = Repo.get(Hexpm.UserSession, current_session.id)
      assert reloaded.revoked_at == nil
    end

    test "returns 404 for non-existent session", %{conn: conn} do
      conn = delete(conn, ~p"/dashboard/sessions?id=99999")

      assert html_response(conn, 404)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session not found"
    end

    test "returns 404 for expired session", %{conn: conn, user: user} do
      # Create an expired session
      {:ok, session, _token} =
        UserSessions.create_browser_session(user, name: "Expired", audit: test_audit_data(user))

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update!(Hexpm.UserSession.changeset(session, %{expires_at: past_time}))

      conn = delete(conn, ~p"/dashboard/sessions?id=#{session.id}")

      assert html_response(conn, 404)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session not found"
    end

    test "handles already revoked session", %{conn: conn, user: user} do
      {:ok, session, _token} =
        UserSessions.create_browser_session(user,
          name: "Already Revoked",
          audit: test_audit_data(user)
        )

      {:ok, _} = UserSessions.revoke(session)

      conn = delete(conn, ~p"/dashboard/sessions?id=#{session.id}")

      # Should return 404 since revoked sessions are excluded from all_for_user
      assert html_response(conn, 404)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session not found"
    end

    test "returns 404 for non-integer session ID string", %{conn: conn} do
      conn = delete(conn, ~p"/dashboard/sessions?id=invalid")

      assert html_response(conn, 404)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session not found"
    end
  end
end
