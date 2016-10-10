defmodule HexWeb.UserControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User

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
end
