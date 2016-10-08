defmodule HexWeb.UserControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Users

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user, password: "hunter42"}
  end

  test "show profile page", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("users/#{c.user.username}")

    assert response(conn, 200) =~ c.user.username
  end

  test "show profile edit page", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("users/#{c.user.username}/edit")

    assert response(conn, 200) =~ "Update your profile"
  end

  test "update profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("users/#{c.user.username}", %{user: %{full_name: "New Name"}})

    assert redirected_to(conn) == "/users/#{c.user.username}"
    assert Users.get(c.user.username).full_name == "New Name"
  end

  test "update profile invalid", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("users/#{c.user.username}", %{user: %{full_name: ""}})

    assert response(conn, 400) =~ "Update your profile"
    assert conn.resp_body =~ "Oops, something went wrong!"
  end
end
