defmodule HexWeb.UserControllerTest do
  use HexWeb.ConnCase, async: true

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42"), password: "hunter42"}
  end

  test "show profile page", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("users/#{c.user.username}")

    assert response(conn, 200) =~ c.user.username
  end
end
