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

  test "choose new password", c do
    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "hunter42")

    # initiate password reset (usually done via api)
    user = User.password_reset(c.user) |> HexWeb.Repo.update!

    # chose new password (using token) to `abcd1234`
    conn = post(build_conn(), "password/choose", %{"username" => user.username, "key" => user.reset_key, "password" => "abcd1234"})
    assert conn.status == 200
    assert conn.assigns.success == true

    # check new password will work
    assert {:ok, {%User{username: "eric"}, nil}} = Auth.password_auth("eric", "abcd1234")
  end
end
