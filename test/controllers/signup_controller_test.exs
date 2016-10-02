defmodule HexWeb.SignupControllerTest do
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
    assert response(conn, 400) =~ "We could not confirm your email"
    refute conn.assigns.success
  end

  test "confirm email with valid key", c do
    conn = get(build_conn(), "confirm", %{"username" => c.user.username, "key" => c.user.confirmation_key})
    assert response(conn, 200) =~ "Your email has been confirmed"
    assert conn.assigns.success
  end
end
