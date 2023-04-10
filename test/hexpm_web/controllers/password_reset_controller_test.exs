defmodule HexpmWeb.PasswordResetControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test
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

      assert response(conn, 200) =~ "Reset your password"

      mock_captcha_success()

      # initiate second reset request
      conn =
        post(build_conn(), "/password/reset", %{
          "username" => c.user.username,
          "h-captcha-response" => "captcha"
        })

      assert response(conn, 200) =~ "Reset your password"

      user =
        Hexpm.Repo.get_by!(User, username: c.user.username)
        |> Hexpm.Repo.preload([:emails, :password_resets])

      assert [reset1, reset2] = user.password_resets

      # check email was sent with correct token
      assert_delivered_email(Hexpm.Emails.password_reset_request(user, reset1))
      assert_delivered_email(Hexpm.Emails.password_reset_request(user, reset2))

      # check reset will succeed
      assert User.can_reset_password?(user, reset1.key)
      assert User.can_reset_password?(user, reset2.key)
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
