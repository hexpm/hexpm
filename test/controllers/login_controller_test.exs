defmodule HexWeb.LoginControllerTest do
  use HexWeb.ConnCase, async: true
  alias HexWeb.Users

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42"), password: "hunter42"}
  end

  test "show log in page" do
    conn = get(build_conn(), "login", %{})
    assert response(conn, 200) =~ "Log in"
  end

  test "log in with correct password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert redirected_to(conn) == "/users/#{c.user.username}"
    assert get_session(conn, "username") == c.user.username

    session_key = get_session(conn, "key")
    assert <<_::binary-32>> = session_key
    assert Users.get(c.user.username).session_key == session_key
  end

  test "log in reuses session key", c do
    user = Users.sign_in(c.user)

    conn = post(build_conn(), "login", %{username: user.username, password: c.password})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    assert get_session(conn, "key") == user.session_key
  end

  test "log in with wrong password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "WRONG"})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Invalid username, email or password."
    refute get_session(conn, "username")
  end

  test "log in with unconfirmed email", c do
    Ecto.Changeset.change(hd(c.user.emails), verified: false) |> HexWeb.Repo.update!

    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Email has not been verified yet."
    refute get_session(conn, "username")
  end

  test "log out", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> post("logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "username")
  end
end
