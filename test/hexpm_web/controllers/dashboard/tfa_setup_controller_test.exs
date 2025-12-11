defmodule HexpmWeb.Dashboard.TFAAuthSetupControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  setup do
    %{user_with_tfa: insert(:user_with_tfa), user: insert(:user)}
  end

  describe "get /dashboard/tfa/setup" do
    test "redirects to security if user already has TFA enabled", c do
      conn =
        build_conn()
        |> test_login(c.user_with_tfa)
        |> get("/dashboard/tfa/setup")

      assert redirected_to(conn) == "/dashboard/security"
    end

    test "shows auth code form for user without TFA", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/tfa/setup")

      result = response(conn, 200)
      assert result =~ "Setup Security App"
      # Should generate a session-based secret and display it in the template
      secret = get_session(conn, :tfa_setup_secret)
      assert secret != nil
      assert result =~ secret
    end

    test "redirects to login if user is not logged in" do
      conn =
        build_conn()
        |> get("/dashboard/tfa/setup")

      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Ftfa%2Fsetup"
    end
  end

  describe "post /dashboard/tfa/setup" do
    test "enables TFA with valid token", c do
      # First visit the setup page to generate a session secret
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/tfa/setup")

      # Get the secret from the session
      secret = get_session(conn, :tfa_setup_secret)
      assert secret != nil

      # Generate a valid token
      token = Hexpm.Accounts.TFA.time_based_token(secret)

      # Submit the verification code
      conn =
        conn
        |> recycle()
        |> test_login(c.user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/tfa/setup", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      assert updated_user.tfa.secret == secret
      assert length(updated_user.tfa.recovery_codes) == 10

      assert_delivered_email(Hexpm.Emails.tfa_enabled(updated_user))
    end

    test "fails with invalid token", c do
      # First visit the setup page to generate a session secret
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/tfa/setup")

      secret = get_session(conn, :tfa_setup_secret)
      assert secret != nil

      conn =
        conn
        |> recycle()
        |> test_login(c.user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/tfa/setup", %{"verification_code" => "000000"})

      assert redirected_to(conn) == "/dashboard/tfa/setup"

      # TFA should not be enabled
      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)

      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)
    end

    test "fails without session secret", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/tfa/setup", %{"verification_code" => "123456"})

      assert redirected_to(conn) == "/dashboard/tfa/setup"

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)

      refute Hexpm.Accounts.User.tfa_enabled?(updated_user)
    end

    test "clears session secret after successful enable", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/tfa/setup")

      secret = get_session(conn, :tfa_setup_secret)
      token = Hexpm.Accounts.TFA.time_based_token(secret)

      conn =
        conn
        |> recycle()
        |> test_login(c.user)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/tfa/setup", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"
      refute get_session(conn, :tfa_setup_secret)
    end

    test "user with TFA already enabled cannot enable again", c do
      secret = Hexpm.Accounts.TFA.generate_secret()
      token = Hexpm.Accounts.TFA.time_based_token(secret)

      conn =
        build_conn()
        |> test_login(c.user_with_tfa)
        |> put_session(:tfa_setup_secret, secret)
        |> post("/dashboard/tfa/setup", %{"verification_code" => token})

      # Should redirect to security page with info message
      assert redirected_to(conn) == "/dashboard/security"

      # Original TFA secret should be unchanged
      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user_with_tfa.id)

      assert updated_user.tfa.secret == c.user_with_tfa.tfa.secret
    end
  end
end
