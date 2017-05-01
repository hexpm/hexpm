defmodule Hexpm.Web.LoginControllerTest do
  use Hexpm.ConnCase

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

    assert get_session(conn, "user_id") == c.user.id
    assert last_session().data["user_id"] == c.user.id
  end

  test "log in keeps you logged in", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn = conn |> recycle() |> get("/")
    assert get_session(conn, "user_id") == c.user.id
  end

  test "log in with wrong password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "WRONG"})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Invalid username, email or password."
    refute get_session(conn, "user_id")
    refute last_session().data["user_id"]
  end

  test "log in with unconfirmed email", c do
    Ecto.Changeset.change(hd(c.user.emails), verified: false) |> Hexpm.Repo.update!

    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") == "Email has not been verified yet."
    refute get_session(conn, "user_id")
    refute last_session().data["user_id"]
  end

  test "log out", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: c.password})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn =
      conn
      |> recycle()
      |> post("logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "user_id")
    refute last_session().data["user_id"]
  end
end
