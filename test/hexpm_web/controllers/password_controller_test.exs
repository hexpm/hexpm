defmodule HexpmWeb.PasswordControllerTest do
  use HexpmWeb.ConnCase
  alias Hexpm.Accounts.{Auth, User, Users}
  alias Hexpm.Repo

  setup do
    mock_pwned()
    user = insert(:user, password: Auth.gen_password("hunter42"))
    %{user: user}
  end

  describe "GET /password/new" do
    test "show select new password redirect" do
      conn = get(build_conn(), "/password/new", %{"username" => "username", "key" => "RESET_KEY"})

      assert redirected_to(conn) == "/password/new"
      assert get_session(conn, "reset_username") == "username"
      assert get_session(conn, "reset_key") == "RESET_KEY"
    end

    test "show select new password", c do
      # Need to create a valid password reset first
      Users.password_reset_init(c.user.username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)
      reset_key = hd(user.password_resets).key

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "reset_username" => c.user.username,
          "reset_key" => reset_key
        })
        |> get("/password/new")

      assert conn.status == 200
      assert conn.resp_body =~ "Choose a new password"
      assert conn.resp_body =~ reset_key
    end

    test "redirect to home when accessing without session data" do
      conn = get(build_conn(), "/password/new")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid password reset key."
    end

    test "redirect to password reset when session has invalid key", c do
      # Create a valid reset, but use a different (invalid) key in session
      Users.password_reset_init(c.user.username, audit: audit_data(c.user))

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "reset_username" => c.user.username,
          "reset_key" => "INVALID_KEY_123"
        })
        |> get("/password/new")

      assert redirected_to(conn) == "/password/reset"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This password reset link has expired or already been used."

      # Verify session was cleared
      refute get_session(conn, "reset_username")
      refute get_session(conn, "reset_key")
    end

    test "redirect when trying to access with used reset key", c do
      # Create and immediately use a reset key
      Users.password_reset_init(c.user.username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)
      reset_key = hd(user.password_resets).key

      # Complete the password reset (this consumes/deletes the key)
      Users.password_reset_finish(
        c.user.username,
        reset_key,
        %{"password" => "new_pass123", "password_confirmation" => "new_pass123"},
        true,
        audit: audit_data(c.user)
      )

      # Now try to access the form with the same (now deleted) key
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "reset_username" => c.user.username,
          "reset_key" => reset_key
        })
        |> get("/password/new")

      assert redirected_to(conn) == "/password/reset"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This password reset link has expired or already been used."
    end
  end

  describe "POST /password/new" do
    test "submit new password", c do
      username = c.user.username
      assert {:ok, %{user: %User{username: ^username}}} = Auth.password_auth(username, "hunter42")

      # initiate password reset (usually done via api)
      Users.password_reset_init(username, audit: audit_data(c.user))

      user = Repo.preload(c.user, :password_resets)

      # chose new password (using token) to `abcd1234`
      conn =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => hd(user.password_resets).key,
            "password" => "abcd1234",
            "password_confirmation" => "abcd1234"
          }
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "password has been changed"
      refute get_session(conn, "session_token")

      # check new password will work
      assert {:ok, %{user: %User{username: ^username}}} = Auth.password_auth(username, "abcd1234")
    end

    test "do not allow changing password with wrong key", c do
      username = c.user.username
      Users.password_reset_init(username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => "WRONG",
            "password" => "abcd1234",
            "password_confirmation" => "abcd1234"
          }
        })

      response(conn, 302)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This password reset link has expired or already been used. Please request a new one."
    end

    test "do not allow changing password with changed primary email", c do
      username = c.user.username
      Users.password_reset_init(username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)
      Repo.delete!(hd(c.user.emails))
      insert(:email, user: user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => hd(user.password_resets).key,
            "password" => "abcd1234",
            "password_confirmation" => "abcd1234"
          }
        })

      response(conn, 302)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This password reset link has expired or already been used. Please request a new one."
    end

    test "prevent reusing reset key after successful password change", c do
      username = c.user.username
      Users.password_reset_init(username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)
      reset_key = hd(user.password_resets).key

      # First request - should succeed
      conn1 =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => reset_key,
            "password" => "new_pass123",
            "password_confirmation" => "new_pass123"
          }
        })

      assert redirected_to(conn1) == "/"
      assert Phoenix.Flash.get(conn1.assigns.flash, :info) =~ "password has been changed"

      # Second request with same key - should fail gracefully (no crash)
      conn2 =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => reset_key,
            "password" => "another_pass456",
            "password_confirmation" => "another_pass456"
          }
        })

      assert redirected_to(conn2) == "/password/reset"

      assert Phoenix.Flash.get(conn2.assigns.flash, :error) ==
               "This password reset link has expired or already been used. Please request a new one."

      # Verify password wasn't changed to the second attempt
      assert :error = Auth.password_auth(username, "another_pass456")
      # Verify first password still works
      assert {:ok, %{user: %User{username: ^username}}} =
               Auth.password_auth(username, "new_pass123")
    end

    test "revokes all access (keys, sessions, tokens) when checkbox checked", c do
      alias Hexpm.{UserSessions, OAuth}

      username = c.user.username

      # Create API key
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(c.user, %{"name" => "test_key", "permissions" => []},
          audit: audit_data(c.user)
        )

      # Create browser session
      {:ok, browser_session, _token} =
        UserSessions.create_browser_session(c.user,
          name: "Test Browser",
          audit: test_audit_data(c.user)
        )

      # Create OAuth session and token
      client = insert(:oauth_client)

      {:ok, oauth_token} =
        OAuth.Tokens.create_session_and_token_for_user(
          c.user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true,
          name: "Test OAuth",
          audit: test_audit_data(c.user)
        )

      oauth_session = Repo.get(Hexpm.UserSession, oauth_token.user_session_id)

      # Initiate password reset
      Users.password_reset_init(username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)

      # Reset password with checkbox checked (default)
      conn =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => hd(user.password_resets).key,
            "password" => "new_password123",
            "password_confirmation" => "new_password123",
            "revoke_all_access" => "yes"
          }
        })

      assert redirected_to(conn) == "/"

      # Verify API key was revoked
      reloaded_key = Repo.get(Hexpm.Accounts.Key, key.id)
      assert reloaded_key.revoke_at != nil

      # Verify browser session was revoked
      reloaded_browser = Repo.get(Hexpm.UserSession, browser_session.id)
      assert reloaded_browser.revoked_at != nil

      # Verify OAuth session was revoked
      reloaded_oauth_session = Repo.get(Hexpm.UserSession, oauth_session.id)
      assert reloaded_oauth_session.revoked_at != nil

      # Verify OAuth token was revoked
      reloaded_token = Repo.get(OAuth.Token, oauth_token.id)
      assert reloaded_token.revoked_at != nil
    end

    test "revokes only sessions and tokens when checkbox unchecked", c do
      alias Hexpm.{UserSessions, OAuth}

      username = c.user.username

      # Create API key
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(c.user, %{"name" => "test_key", "permissions" => []},
          audit: audit_data(c.user)
        )

      # Create browser session
      {:ok, browser_session, _token} =
        UserSessions.create_browser_session(c.user,
          name: "Test Browser",
          audit: test_audit_data(c.user)
        )

      # Create OAuth session and token
      client = insert(:oauth_client)

      {:ok, oauth_token} =
        OAuth.Tokens.create_session_and_token_for_user(
          c.user,
          client.client_id,
          ["api"],
          "authorization_code",
          "test_code",
          with_refresh_token: true,
          name: "Test OAuth",
          audit: test_audit_data(c.user)
        )

      oauth_session = Repo.get(Hexpm.UserSession, oauth_token.user_session_id)

      # Initiate password reset
      Users.password_reset_init(username, audit: audit_data(c.user))
      user = Repo.preload(c.user, :password_resets)

      # Reset password with checkbox unchecked
      conn =
        build_conn()
        |> test_login(user)
        |> post("/password/new", %{
          "user" => %{
            "username" => user.username,
            "key" => hd(user.password_resets).key,
            "password" => "new_password123",
            "password_confirmation" => "new_password123",
            "revoke_all_access" => "no"
          }
        })

      assert redirected_to(conn) == "/"

      # Verify API key was NOT revoked
      reloaded_key = Repo.get(Hexpm.Accounts.Key, key.id)
      assert reloaded_key.revoke_at == nil

      # Verify browser session was revoked
      reloaded_browser = Repo.get(Hexpm.UserSession, browser_session.id)
      assert reloaded_browser.revoked_at != nil

      # Verify OAuth session was revoked
      reloaded_oauth_session = Repo.get(Hexpm.UserSession, oauth_session.id)
      assert reloaded_oauth_session.revoked_at != nil

      # Verify OAuth token was revoked
      reloaded_token = Repo.get(OAuth.Token, oauth_token.id)
      assert reloaded_token.revoked_at != nil
    end
  end
end
