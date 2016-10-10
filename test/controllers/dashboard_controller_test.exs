defmodule HexWeb.DashboardControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Users

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user, password: "hunter42"}
  end

  test "show profile edit page", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
  end

  test "update profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{full_name: "New Name"}})

    assert response(conn, 200) =~ "Public profile"
    assert Users.get(c.user.username).full_name == "New Name"
  end

  test "update profile invalid", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{full_name: ""}})

    assert response(conn, 400) =~ "Public profile"
    assert conn.resp_body =~ "Oops, something went wrong!"
  end
end
