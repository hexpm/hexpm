defmodule HexpmWeb.Dashboard.SecurityControllerTest.TFAVerification do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "post /dashboard/security/verify-tfa-code" do
    test "with invalid token", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => "000000"})

      assert redirected_to(conn) == "/dashboard/security?tfa_error=invalid_code"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your verification code was incorrect. Please try again."
    end

    test "with valid token", c do
      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/security/verify-tfa-code", %{"verification_code" => token})

      assert redirected_to(conn) == "/dashboard/security"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Two-factor authentication has been successfully enabled!"

      updated_user =
        Hexpm.Accounts.User
        |> Hexpm.Repo.get(c.user.id)
        |> Hexpm.Repo.preload(:emails)

      assert updated_user.tfa.tfa_enabled == true
      assert updated_user.tfa.app_enabled == true
      assert_delivered_email(Hexpm.Emails.tfa_enabled(updated_user))
    end

    test "without tfa secret started", _c do
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
  end
end
