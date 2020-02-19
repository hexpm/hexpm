defmodule HexpmWeb.PasswordResetControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test
  alias Hexpm.Accounts.User

  setup do
    %{user: insert(:user)}
  end

  test "show reset your password" do
    conn = get(build_conn(), "password/reset", %{})
    assert response(conn, 200) =~ "Reset your password"
  end

  test "email is sent with reset_token when password is reset", c do
    # initiate reset request
    conn = post(build_conn(), "password/reset", %{"username" => c.user.username})
    assert response(conn, 200) =~ "Reset your password"

    # initiate second reset request
    conn = post(build_conn(), "password/reset", %{"username" => c.user.username})
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
end
