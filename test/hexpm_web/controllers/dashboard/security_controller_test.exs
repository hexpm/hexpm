defmodule HexpmWeb.Dashboard.SecurityControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.Auth

  setup do
    mock_pwned()
    %{user: insert(:user_with_tfa)}
  end

  describe "get /dashboard/security" do
    test "when tfa is enabled", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/security")

      result = response(conn, 200)
      assert result =~ "Two-factor security"
    end

    test "redirects to setup if tfa is not enabled" do
      tfa = build(:tfa, app_enabled: false)
      user = insert(:user_with_tfa, tfa: tfa)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      assert redirected_to(conn) == "/dashboard/tfa/setup"
    end
  end

  describe "post /dashboard_security/enable-tfa" do
    test "sets the users tfa to enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/enable-tfa")

      user = Hexpm.Repo.get(Hexpm.Accounts.User, user.id)
      assert user.tfa.tfa_enabled
      assert redirected_to(conn) == "/dashboard/tfa/setup"
    end
  end

  describe "post /dashboard_security/disable-tfa" do
    test "sets the users tfa to disabled", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/disable-tfa")

      user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      refute user.tfa.tfa_enabled
      assert redirected_to(conn) == "/dashboard/security"
    end
  end

  describe "post /dashboard_security/rotate-recovery-codes" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/rotate-recovery-codes")

      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      assert updated_user.tfa.recovery_codes != c.user.tfa.recovery_codes
      assert redirected_to(conn) == "/dashboard/security"
    end
  end

  describe "post /dashboard_security/reset-auth-app" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/reset-auth-app")

      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      refute updated_user.tfa.app_enabled
      assert redirected_to(conn) == "/dashboard/tfa/setup"
    end
  end

  describe "post /dashboard/security/change-password" do
    test "shows password change form on security page" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/security")

      assert response(conn, 200) =~ "Password authentication"
      assert response(conn, 200) =~ "Current password"
    end

    test "update password", _c do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          user: %{
            password_current: "password",
            password: "newpass",
            password_confirmation: "newpass"
          }
        })

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your password has been updated"
      assert {:ok, _} = Auth.password_auth(user.username, "newpass")
      assert :error = Auth.password_auth(user.username, "password")

      assert_delivered_email(Hexpm.Emails.password_changed(user))
    end

    test "update password invalid current password" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          user: %{
            password_current: "WRONG",
            password: "newpass",
            password_confirmation: "newpass"
          }
        })

      assert response(conn, 400) =~ "Password authentication"
      assert {:ok, _} = Auth.password_auth(user.username, "password")
    end

    test "update password invalid confirmation password" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          user: %{
            password_current: "password",
            password: "newpass",
            password_confirmation: "WRONG"
          }
        })

      assert response(conn, 400) =~ "Password authentication"
      assert {:ok, _} = Auth.password_auth(user.username, "password")
      assert :error = Auth.password_auth(user.username, "newpass")
    end

    test "update password missing current password" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/change-password", %{
          user: %{password: "newpass", password_confirmation: "newpass"}
        })

      assert response(conn, 400) =~ "Password authentication"
      assert {:ok, _} = Auth.password_auth(user.username, "password")
      assert :error = Auth.password_auth(user.username, "newpass")
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
      assert Phoenix.Flash.get(conn.assigns.flash, "info") == "Password added successfully."

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

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~ "should be at least 7 character(s)"
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

      assert redirected_to(conn) == "/dashboard/security"
      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~ "does not match password"
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
      assert Phoenix.Flash.get(conn.assigns.flash, "info") == "Password removed successfully."

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

      assert Phoenix.Flash.get(conn.assigns.flash, "error") =~
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
