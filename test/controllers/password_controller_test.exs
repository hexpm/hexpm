defmodule HexWeb.PasswordControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Auth
  alias HexWeb.User

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user}
  end

  test "show reset your password" do
    conn = get(build_conn(), "password/reset", %{})
    assert conn.resp_body =~ "Reset your password"
    assert conn.status == 200
  end

  test "email is sent with reset_token when password is reset", c do
    # initiate reset request
    conn = post(build_conn(), "password/reset", %{"username" => c.user.username})
    assert conn.resp_body =~ "Reset your password"
    assert conn.status == 200

    # check email was sent with correct token
    user = HexWeb.Repo.get_by!(User, username: c.user.username)
    {subject, contents} = HexWeb.Email.Local.read(c.user.email)
    assert subject =~ "Hex.pm"
    assert contents =~ "#{user.reset_key}"

    # check reset will succeed
    assert User.reset?(user, user.reset_key) == true
  end

  test "show select new password", c do
    conn = get(build_conn(), "password/new", %{"username" => c.user.username, "key" => "RESET_KEY"})
    assert conn.resp_body =~ "Choose a new password<"
    assert conn.resp_body =~ "RESET_KEY"
    assert conn.status == 200
  end

  test "submit new password", c do
    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "hunter42")

    # initiate password reset (usually done via api)
    user = User.password_reset(c.user) |> HexWeb.Repo.update!

    # chose new password (using token) to `abcd1234`
    conn = post(build_conn(), "password/new", %{"username" => user.username, "key" => user.reset_key, "password" => "abcd1234"})
    assert conn.status == 200
    assert conn.assigns.success == true

    # check new password will work
    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "abcd1234")
  end
end
