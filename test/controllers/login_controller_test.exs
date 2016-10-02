defmodule HexWeb.LoginControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
      |> HexWeb.Repo.insert!

    %{user: user, password: "hunter42"}
  end

  test "show log in page" do
    conn = get(build_conn(), "login", %{})
    assert response(conn, 200) =~ "Log in"
  end

  test "log in with correct password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert redirected_to(conn) == "/"
    assert get_session(conn, "username") == c.user.username
  end

  test "log in with wrong password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "WRONG"})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Invalid username, email or password"
    refute get_session(conn, "username")
  end

  test "log in with unconfirmed email", c do
    Ecto.Changeset.change(c.user, confirmed: false) |> HexWeb.Repo.update!

    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Email has not been confirmed yet"
    refute get_session(conn, "username")
  end

  test "log out", c do
    conn =
      build_conn()
      |> my_put_session("username", c.user.username)
      |> post("logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "username")
  end

  # See: https://github.com/elixir-lang/plug/issues/455
  defp my_put_session(conn, key, value) do
    private = Map.update(conn.private, :plug_session, %{key => value}, &Map.put(&1, key, value))
    %{conn | private: private}
  end
end
