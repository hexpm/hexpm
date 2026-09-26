defmodule HexpmWeb.PasswordResetControllerTest do
  use HexpmWeb.ConnCase, async: true
  alias Hexpm.Accounts.User

  setup do
    %{user: insert(:user)}
  end

  describe "GET /password/reset" do
    test "show reset your password" do
      conn = get(build_conn(), "/password/reset", %{})
      assert response(conn, 200) =~ "Reset your password"
    end
  end

  describe "POST /password/reset" do
    test "email is sent with reset_token when password is reset", c do
      mock_captcha_success()

      # initiate reset request
      conn =
        post(build_conn(), "/password/reset", %{
          "username" => c.user.username,
          "h-captcha-response" => "captcha"
        })

      assert response(conn, 200) =~ "Check your email"
      first_key = password_reset_key()

      mock_captcha_success()

      # initiate second reset request
      conn =
        post(build_conn(), "/password/reset", %{
          "username" => c.user.username,
          "h-captcha-response" => "captcha"
        })

      assert response(conn, 200) =~ "Check your email"
      second_key = password_reset_key()

      user =
        Hexpm.Repo.get_by!(User, username: c.user.username)
        |> Hexpm.Repo.preload([:emails, :password_resets])

      assert [_, _] = user.password_resets

      # both mailed keys reset the password
      assert User.can_reset_password?(user, first_key)
      assert User.can_reset_password?(user, second_key)
    end

    test "captha failed", c do
      mock_captcha_failure()

      # initiate reset request
      conn =
        post(build_conn(), "/password/reset", %{
          "username" => c.user.username,
          "h-captcha-response" => "captcha"
        })

      assert response(conn, 400) =~ "Please complete the captcha to reset password"
    end
  end
end
