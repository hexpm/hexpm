defmodule HexpmWeb.Dashboard.SecurityControllerTest do
  use HexpmWeb.ConnCase, async: true

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
end
