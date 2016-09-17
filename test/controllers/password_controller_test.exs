defmodule HexWeb.PasswordControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Auth
  alias HexWeb.User

  test "reset user password" do
    # create user and test with current password
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "hunter42")

    # initiate password reset (usually done via api)
    {:ok, %User{reset_key: reset_key} = user} =
      User.password_reset(user)
      |> HexWeb.Repo.update

    # reset the password (using token) to `abcd1234`
    conn = post(build_conn(), "password/reset", %{"username" => user.username, "key" => reset_key, "password" => "abcd1234"})
    assert conn.status == 200
    assert conn.assigns[:success] == true

    # check new password will work
    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "abcd1234")
  end

  test "confirm" do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    # confirm with invalid confirmation key
    conn = get(build_conn(), "password/confirm", %{"username" => user.username, "key" => "invalid"})
    assert conn.status == 200
    assert conn.assigns[:success] == false

    # confirm with valid confirmation key
    conn = get(build_conn(), "password/confirm", %{"username" => user.username, "key" => user.confirmation_key})
    assert conn.status == 200
    assert conn.assigns[:success] == true
  end
end
