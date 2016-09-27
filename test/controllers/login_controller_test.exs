defmodule HexWeb.LoginControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user}
  end

  test "confirm email with invalid key", c do
    conn = get(build_conn(), "confirm", %{"username" => c.user.username, "key" => "invalid"})
    assert conn.status == 200
    assert conn.assigns.success == false
  end

  test "confirm email with valid key", c do
    conn = get(build_conn(), "confirm", %{"username" => c.user.username, "key" => c.user.confirmation_key})
    assert conn.status == 200
    assert conn.assigns.success == true
  end
end
