defmodule HexpmWeb.SudoControllerTest do
  use HexpmWeb.ConnCase

  alias HexpmWeb.Plugs.Sudo

  setup do
    mock_pwned()
    :ok
  end

  describe "GET /sudo" do
    test "redirects to login if not authenticated" do
      conn = get(build_conn(), ~p"/sudo")
      assert redirected_to(conn) =~ "/login"
    end

    test "shows password form for user with password (no 2FA)" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo")

      assert html_response(conn, 200) =~ "Verify your identity"
      assert html_response(conn, 200) =~ "Password"
      refute html_response(conn, 200) =~ "Authentication Code"
    end

    test "shows GitHub button for user with linked GitHub (no 2FA)" do
      user = insert(:user, password: nil)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo")

      assert html_response(conn, 200) =~ "Re-authenticate with GitHub"
      refute html_response(conn, 200) =~ "type=\"password\""
    end

    test "shows both options when user has password and GitHub (no 2FA)" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo")

      assert html_response(conn, 200) =~ "Re-authenticate with GitHub"
      assert html_response(conn, 200) =~ "type=\"password\""
    end

    test "shows only 2FA form when 2FA enabled (no password/GitHub options)" do
      user = insert(:user_with_tfa)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo")

      assert html_response(conn, 200) =~ "Authentication Code"
      assert html_response(conn, 200) =~ "recovery code"
      refute html_response(conn, 200) =~ "Re-authenticate with GitHub"
      refute html_response(conn, 200) =~ "type=\"password\""
    end
  end

  describe "POST /sudo with password" do
    test "verifies correct password and sets sudo" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> put_session("sudo_return_to", "/dashboard/security")
        |> post(~p"/sudo", %{"type" => "password", "password" => "password"})

      assert redirected_to(conn) == "/dashboard/security"
      assert Sudo.sudo_active?(conn)
    end

    test "rejects incorrect password" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "password", "password" => "wrong"})

      assert html_response(conn, 200) =~ "Incorrect password"
      refute Sudo.sudo_active?(conn)
    end

    test "returns error when 2FA enabled" do
      user = insert(:user_with_tfa)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "password", "password" => "password"})

      assert html_response(conn, 200) =~ "authenticator app or recovery code"
      refute Sudo.sudo_active?(conn)
    end

    test "rate limits password attempts" do
      user = insert(:user)
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      # Make 5 failed attempts to exhaust the limit
      for _ <- 1..5 do
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "password", "password" => "wrong"})
      end

      # 6th attempt should be rate limited
      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "password", "password" => "wrong"})

      assert html_response(conn, 200) =~ "Too many incorrect password attempts"
    end
  end

  describe "POST /sudo with 2FA code" do
    test "verifies correct 2FA code and sets sudo" do
      user = insert(:user_with_tfa)
      code = Hexpm.Accounts.TFA.time_based_token(user.tfa.secret)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> put_session("sudo_return_to", "/dashboard/keys")
        |> post(~p"/sudo", %{"type" => "tfa", "code" => code})

      assert redirected_to(conn) == "/dashboard/keys"
      assert Sudo.sudo_active?(conn)
    end

    test "rejects invalid 2FA code" do
      user = insert(:user_with_tfa)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "tfa", "code" => "000000"})

      assert html_response(conn, 200) =~ "Incorrect authentication code"
      refute Sudo.sudo_active?(conn)
    end

    test "returns error when 2FA not enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "tfa", "code" => "123456"})

      assert html_response(conn, 200) =~ "Two-factor authentication is not enabled"
    end

    test "rate limits 2FA attempts" do
      user = insert(:user_with_tfa)
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      # Make 5 failed attempts to exhaust the limit
      for _ <- 1..5 do
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "tfa", "code" => "000000"})
      end

      # 6th attempt should be rate limited
      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "tfa", "code" => "000000"})

      assert html_response(conn, 200) =~ "Too many incorrect code attempts"
    end
  end

  describe "GET /sudo/recovery" do
    test "shows recovery code form when 2FA enabled" do
      user = insert(:user_with_tfa)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo/recovery")

      assert html_response(conn, 200) =~ "recovery code"
      assert html_response(conn, 200) =~ "xxxx-xxxx-xxxx-xxxx"
    end

    test "redirects when 2FA not enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo/recovery")

      assert redirected_to(conn) == "/sudo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not enabled"
    end
  end

  describe "POST /sudo/recovery" do
    test "verifies correct recovery code, marks it used, and sets sudo" do
      user = insert(:user_with_tfa)
      [first_code | _rest] = user.tfa.recovery_codes
      code_string = first_code.code

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> put_session("sudo_return_to", "/dashboard/email")
        |> post(~p"/sudo/recovery", %{"code" => code_string})

      assert redirected_to(conn) == "/dashboard/email"
      assert Sudo.sudo_active?(conn)

      # Verify code was marked as used
      updated_user = Hexpm.Accounts.Users.get_by_id(user.id)
      used_code = Enum.find(updated_user.tfa.recovery_codes, &(&1.code == code_string))
      assert used_code.used_at
    end

    test "rejects invalid recovery code" do
      user = insert(:user_with_tfa)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo/recovery", %{"code" => "aaaa-bbbb-cccc-dddd"})

      assert html_response(conn, 200) =~ "Incorrect recovery code"
      refute Sudo.sudo_active?(conn)
    end

    test "rejects invalid recovery code format" do
      user = insert(:user_with_tfa)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo/recovery", %{"code" => "invalid"})

      assert html_response(conn, 200) =~ "Invalid recovery code format"
    end

    test "redirects when 2FA not enabled" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo/recovery", %{"code" => "aaaa-bbbb-cccc-dddd"})

      assert redirected_to(conn) == "/sudo"
    end
  end

  describe "GET /sudo/github" do
    test "redirects to OAuth when 2FA disabled and GitHub linked" do
      user = insert(:user)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo/github")

      assert redirected_to(conn) == "/auth/github"
      assert get_session(conn, "sudo_verification")
    end

    test "redirects back with error when 2FA enabled" do
      user = insert(:user_with_tfa)
      insert(:user_provider, user: user, provider: "github")

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo/github")

      assert redirected_to(conn) == "/sudo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "authenticator app or recovery code"
    end

    test "redirects back with error when no GitHub linked" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> get(~p"/sudo/github")

      assert redirected_to(conn) == "/sudo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No GitHub account linked"
    end
  end

  describe "redirects to sudo_return_to on success" do
    test "redirects to stored path after password verification" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> put_session("sudo_return_to", "/dashboard/keys")
        |> post(~p"/sudo", %{"type" => "password", "password" => "password"})

      assert redirected_to(conn) == "/dashboard/keys"
      refute get_session(conn, "sudo_return_to")
    end

    test "redirects to default path when no return_to stored" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user, sudo: false)
        |> post(~p"/sudo", %{"type" => "password", "password" => "password"})

      assert redirected_to(conn) == "/dashboard/security"
    end
  end
end
