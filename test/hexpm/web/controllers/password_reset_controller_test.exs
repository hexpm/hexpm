defmodule Hexpm.Web.PasswordResetControllerTest do
  use Hexpm.ConnCase, async: true
  use Bamboo.Test
  alias Hexpm.Accounts.User

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42")}
  end

  test "show reset your password" do
    conn = get(build_conn(), "password/reset", %{})
    assert response(conn, 200) =~ "Reset your password"
  end

  test "email is sent with reset_token when password is reset", c do
    # initiate reset request
    conn = post(build_conn(), "password/reset", %{"username" => c.user.username})
    assert response(conn, 200) =~ "Reset your password"

    # check email was sent with correct token
    user = Hexpm.Repo.get_by!(User, username: c.user.username) |> Hexpm.Repo.preload(:emails)
    assert_delivered_email Hexpm.Emails.password_reset_request(user)

    # check reset will succeed
    assert User.password_reset?(user, user.reset_key) == true
  end
end
