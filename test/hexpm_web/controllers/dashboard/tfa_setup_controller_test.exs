defmodule HexpmWeb.Dashboard.TFAAuthSetupControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /dashboard/tfa/setup" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", c.user.id)
        |> get("/dashboard/tfa/setup")

      result = response(conn, 200)
      assert result =~ "Setup Security App"
    end

    test "redirects to homepage if user is not logged in" do
      conn =
        build_conn()
        |> get("/dashboard/tfa/setup")

      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Ftfa%2Fsetup"
    end
  end

  describe "post /dashboard/tfa/setup" do
    test "with invalid token", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/dashboard/tfa/setup", %{"verification_code" => "000000"})

      assert redirected_to(conn) == "/dashboard/tfa/setup"
    end

    test "with valid token", c do
      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/dashboard/tfa/setup", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      assert_delivered_email(Hexpm.Emails.tfa_enabled_app(updated_user))
    end
  end
end
