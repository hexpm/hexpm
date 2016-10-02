defmodule HexWeb.PasswordResetControllerTest do
  use HexWeb.ConnCase, async: true
  alias HexWeb.User

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user}
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
    user = HexWeb.Repo.get_by!(User, username: c.user.username)
    {subject, contents} = HexWeb.Email.Local.read(c.user.email)
    assert subject =~ "Hex.pm"
    assert contents =~ "#{user.reset_key}"

    # check reset will succeed
    assert User.reset?(user, user.reset_key) == true
  end
end
