defmodule HexpmWeb.Dashboard.SecurityControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  setup do
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

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(user.id)
        |> Hexpm.Repo.preload(:emails)

      assert updated_user.tfa.tfa_enabled
      assert redirected_to(conn) == "/dashboard/tfa/setup"

      assert_delivered_email(Hexpm.Emails.tfa_enabled(updated_user))
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

      refute updated_user.tfa.tfa_enabled
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

  describe "post /dashboard_security/reset-auth-app" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/reset-auth-app")

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      refute updated_user.tfa.app_enabled
      assert redirected_to(conn) == "/dashboard/tfa/setup"

      assert_delivered_email(Hexpm.Emails.tfa_disabled_app(updated_user))
    end
  end
end
