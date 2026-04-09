defmodule HexpmWeb.Dashboard.SecurityControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.Auth

  setup do
    mock_pwned()
    user = insert(:user_with_tfa)
    %{user: user}
  end

  describe "get /dashboard/security" do
    test "shows Two-Factor Authentication section with disable button when enabled", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/security")

      result = response(conn, 200)
      assert result =~ "Two-Factor Authentication"
      assert result =~ "Disable"
    end

    test "shows enable link if tfa is not enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      result = response(conn, 200)
      assert result =~ "Two-Factor Authentication"
      assert result =~ "Enable"
    end

    test "shows modal when tfa_setup_secret is in session" do
      user = insert(:user)
      secret = Hexpm.Accounts.TFA.generate_secret()

      conn =
        build_conn()
        |> test_login(user)
        |> put_session(:tfa_setup_secret, secret)
        |> get("/dashboard/security?show_tfa_modal=true")

      result = response(conn, 200)
      assert result =~ "Two-Factor Authentication"
      assert result =~ secret
    end

    test "does NOT show remove password button when user has no providers" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      result = response(conn, 200)

      refute result =~ "Remove password"
      assert result =~ "You must connect a GitHub account before you can remove your password"
    end

    test "shows remove password button when user has GitHub connected" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      result = response(conn, 200)

      assert result =~ "Remove Password"
      refute result =~ "You must connect a GitHub account before you can remove your password"
    end
  end

  describe "post /dashboard_security/enable-tfa" do
    test "generates secret and stores in session" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/enable-tfa")

      # Secret should be stored in session
      assert get_session(conn, :tfa_setup_secret)

      # Should redirect to security page with modal open
      assert redirected_to(conn) == "/dashboard/security?show_tfa_modal=true"

      # TFA should NOT be enabled in DB
      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, user.id)
      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)
    end
  end

  describe "post /dashboard_security/disable-tfa" do
    test "sets the users tfa to disabled", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/disable-tfa")

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)
      assert redirected_to(conn) == "/dashboard/security"

      assert_delivered_email(Hexpm.Emails.tfa_disabled(updated_user))
    end
  end

  describe "post /dashboard_security/rotate-recovery-codes" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/rotate-recovery-codes")

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      assert updated_user.tfa.recovery_codes != c.user.tfa.recovery_codes
      assert redirected_to(conn) == "/dashboard/security"

      assert_delivered_email(Hexpm.Emails.tfa_rotate_recovery_codes(updated_user))
    end
  end

  describe "post /dashboard/security/reset-auth-app" do
    test "disables TFA and generates new session secret", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/reset-auth-app")

      # TFA should be disabled in DB
      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)

      # New secret should be stored in session for re-setup
      assert get_session(conn, :tfa_setup_secret)

      assert redirected_to(conn) == "/dashboard/security?show_tfa_modal=true"
      assert_delivered_email(Hexpm.Emails.tfa_disabled(updated_user))
    end
  end

  describe "post /dashboard/security/change-password" do
    test "shows password change form on security page" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      result = response(conn, 200)
      assert result =~ "Current Password"
    end

    test "changes password and verifies in DB", _c do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          "user" => %{
            "password_current" => "password",
            "password" => "newpassxx",
            "password_confirmation" => "newpassxx"
          }
        })

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your password has been updated"
      assert {:ok, _} = Auth.password_auth(user.username, "newpassxx")
      assert :error = Auth.password_auth(user.username, "password")

      assert_delivered_email(Hexpm.Emails.password_changed(user))
    end

    test "fails to change password with incorrect old password", _c do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          "user" => %{
            "password_current" => "wrong_password",
            "password" => "newpassxx",
            "password_confirmation" => "newpassxx"
          }
        })

      result = response(conn, 400)
      assert result =~ "incorrect password"
      assert {:ok, _} = Auth.password_auth(user.username, "password")
    end

    test "fails to change password with wrong confirmation", _c do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          "user" => %{
            "password_current" => "password",
            "password" => "newpassxx",
            "password_confirmation" => "WRONG"
          }
        })

      response(conn, 400)
      assert {:ok, _} = Auth.password_auth(user.username, "password")
      assert :error = Auth.password_auth(user.username, "newpassxx")
    end

    test "fails to change password without current password", _c do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          "user" => %{
            "password" => "newpassxx",
            "password_confirmation" => "newpassxx"
          }
        })

      response(conn, 400)
      assert {:ok, _} = Auth.password_auth(user.username, "password")
      assert :error = Auth.password_auth(user.username, "newpassxx")
    end
  end

  describe "post /dashboard/security/verify-tfa-code" do
    test "enables TFA with valid code" do
      user = insert(:user)
      secret = Hexpm.Accounts.TFA.generate_secret()
      token = Hexpm.Accounts.TFA.time_based_token(secret)

      conn =
        build_conn()
        |> test_login(user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Two-factor authentication has been successfully enabled!"

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(user.id)
        |> Hexpm.Repo.preload(:emails)

      assert Hexpm.Accounts.User.tfa_enabled?(updated_user)
      assert updated_user.tfa.secret == secret
      assert_delivered_email(Hexpm.Emails.tfa_enabled(updated_user))

      # Session secret should be cleared
      refute get_session(conn, :tfa_setup_secret)
    end

    test "fails with invalid code" do
      user = insert(:user)
      secret = Hexpm.Accounts.TFA.generate_secret()

      conn =
        build_conn()
        |> test_login(user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => "000000"})

      assert redirected_to(conn) == "/dashboard/security?tfa_error=invalid_code"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your verification code was incorrect. Please try again."

      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, user.id)
      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)
    end

    test "fails without session secret" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => "123456"})

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Two-factor authentication setup has not been started."
    end

    test "redirects to login if user is not logged in" do
      conn =
        build_conn()
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => "123456"})

      assert redirected_to(conn) =~ "/login?return="
    end

    test "does not re-enable TFA when already enabled", c do
      secret = Hexpm.Accounts.TFA.generate_secret()
      token = Hexpm.Accounts.TFA.time_based_token(secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"

      # Original TFA secret should be unchanged
      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)

      assert updated_user.tfa.secret == c.user.tfa.secret
    end
  end

  describe "POST /dashboard/security/disconnect-github" do
    test "disconnects GitHub when user has password" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github", provider_uid: "12345")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/disconnect-github")

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, "info") ==
               "GitHub account disconnected successfully."

      refute Hexpm.Accounts.UserProviders.get_by_provider("github", "12345")
    end

    test "fails to disconnect GitHub when user has no password" do
      user = insert(:user, password: nil)
      insert(:user_provider, user: user, provider: "github", provider_uid: "54321")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/disconnect-github")

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
               "Cannot disconnect GitHub account. Please add a password first."

      # GitHub should still be connected
      assert Hexpm.Accounts.UserProviders.get_by_provider("github", "54321")
    end

    test "shows error when GitHub is not connected" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/disconnect-github")

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") == "GitHub account is not connected."
    end

    test "requires login" do
      conn = post(build_conn(), "/dashboard/security/disconnect-github")
      assert redirected_to(conn) =~ "/login"
    end
  end

  describe "POST /dashboard/security/add-password" do
    test "adds password to GitHub-only account" do
      user = insert(:user, password: nil)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/add-password", %{
          "user" => %{
            "password" => "newpassword123",
            "password_confirmation" => "newpassword123"
          }
        })

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Password added successfully."

      updated_user = Hexpm.Accounts.Users.get_by_id(user.id)
      assert updated_user.password
    end

    test "validates password strength" do
      user = insert(:user, password: nil)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/add-password", %{
          "user" => %{
            "password" => "weak",
            "password_confirmation" => "weak"
          }
        })

      response(conn, 400)
    end

    test "validates password confirmation" do
      user = insert(:user, password: nil)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/add-password", %{
          "user" => %{
            "password" => "password123",
            "password_confirmation" => "different123"
          }
        })

      response(conn, 400)
    end

    test "requires login" do
      conn = post(build_conn(), "/dashboard/security/add-password", %{"user" => %{}})
      assert redirected_to(conn) =~ "/login"
    end
  end

  describe "POST /dashboard/security/remove-password" do
    test "removes password when GitHub is connected" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/remove-password")

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Password removed successfully."

      updated_user = Hexpm.Accounts.Users.get_by_id(user.id)
      refute updated_user.password
    end

    test "fails to remove password when no GitHub is connected" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/remove-password")

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Failed to remove password: cannot remove last authentication method"

      # Password should still exist
      updated_user = Hexpm.Accounts.Users.get_by_id(user.id)
      assert updated_user.password
    end

    test "requires login" do
      conn = post(build_conn(), "/dashboard/security/remove-password")
      assert redirected_to(conn) =~ "/login"
    end
  end
end
