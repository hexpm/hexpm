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

      assert redirected_to(conn) == "/dashboard/two_factor_auth/setup"
    end
  end

  describe "post /dashboard_security/enable_tfa" do
    test "sets the users tfa to enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/security/enable_tfa")

      user = Hexpm.Repo.get(Hexpm.Accounts.User, user.id)
      assert user.tfa.tfa_enabled == true
      assert redirected_to(conn) == "/dashboard/two_factor_auth/setup"
    end
  end

  describe "post /dashboard_security/disable_tfa" do
    test "sets the users tfa to disabled", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/disable_tfa")

      user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      assert user.tfa.tfa_enabled == false
      assert redirected_to(conn) == "/dashboard/security"
    end
  end

  describe "post /dashboard_security/rotate_recovery_codes" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/rotate_recovery_codes")

      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      assert updated_user.tfa.recovery_codes != c.user.tfa.recovery_codes
      assert redirected_to(conn) == "/dashboard/security"
    end
  end

  describe "post /dashboard_security/reset_auth_app" do
    test "changes the recovery codes", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/reset_auth_app")

      updated_user = Hexpm.Repo.get(Hexpm.Accounts.User, c.user.id)
      assert updated_user.tfa.app_enabled == false
      assert redirected_to(conn) == "/dashboard/two_factor_auth/setup"
    end
  end
end
