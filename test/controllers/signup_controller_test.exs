defmodule HexWeb.SignupControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Users

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user}
  end

  test "show create user page" do
    conn = get(build_conn(), "signup")
    assert response(conn, 200) =~ "Sign up"
  end

  test "create user" do
    conn = post(build_conn(), "signup", %{user: %{username: "jose", email: "jose@mail.com", password: "hunter42", full_name: "José"}})

    assert redirected_to(conn) == "/"
    user = Users.get("jose")
    assert user.username == "jose"
    assert user.full_name == "José"
  end

  test "create user invalid" do
    conn = post(build_conn(), "signup", %{user: %{username: "eric", email: "jose@mail.com", password: "hunter42", full_name: "José"}})
    assert response(conn, 400) =~ "Sign up"
    assert conn.resp_body =~ "Oops, something went wrong!"
  end

  test "confirm email with invalid key", c do
    conn = get(build_conn(), "confirm", %{username: c.user.username, key: "invalid"})
    assert response(conn, 400) =~ "We could not confirm your email"
    refute conn.assigns.success
  end

  test "confirm email with valid key", c do
    conn = get(build_conn(), "confirm", %{username: c.user.username, key: c.user.confirmation_key})
    assert response(conn, 200) =~ "Your email has been confirmed"
    assert conn.assigns.success
  end
end
