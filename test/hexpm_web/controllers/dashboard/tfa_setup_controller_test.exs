defmodule HexpmWeb.Dashboard.TFAAuthSetupControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /dashboard/two_factor_auth/setup" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", c.user.id)
        |> get("/dashboard/two_factor_auth/setup")

      result = response(conn, 200)
      assert result =~ "Setup Security App"
    end

    test "redirects to homepage if user is not logged in" do
      conn =
        build_conn()
        |> get("/dashboard/two_factor_auth/setup")

      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Ftwo_factor_auth%2Fsetup"
    end
  end

  describe "post /dashboard/two_factor_auth/setup" do
    test "with invalid token", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/dashboard/two_factor_auth/setup", %{"verification_code" => "000000"})

      assert redirected_to(conn) == "/dashboard/two_factor_auth/setup"
    end

    test "with valid token", c do
      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/dashboard/two_factor_auth/setup", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"
    end
  end
end
