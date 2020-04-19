defmodule HexpmWeb.LoginControllerTest do
  use HexpmWeb.ConnCase
  alias Hexpm.Accounts.Auth

  setup do
    mock_pwned()
    user = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)
    %{user: user, organization: organization}
  end

  test "show log in page" do
    conn = get(build_conn(), "login", %{})
    assert response(conn, 200) =~ "Log in"
  end

  test "log in with correct password", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    assert get_session(conn, "user_id") == c.user.id
    assert last_session().data["user_id"] == c.user.id
  end

  @tag :focus
  test "log in when tfa enabled" do
    user = insert(:user_with_tfa)
    conn = post(build_conn(), "login", %{username: user.username, password: "password"})
    assert redirected_to(conn) == "/two_factor_auth"

    assert get_session(conn, "tfa_user_id") == %{return: nil, uid: user.id}
  end

  test "log in keeps you logged in", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
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
    Ecto.Changeset.change(hd(c.user.emails), verified: false) |> Hexpm.Repo.update!()

    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
    assert response(conn, 400) =~ "Log in"
    assert get_flash(conn, "error") =~ "Email has not been verified yet."
    refute get_session(conn, "user_id")
    refute last_session().data["user_id"]
  end

  test "log out", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn =
      conn
      |> recycle()
      |> post("logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "user_id")
    refute last_session().data["user_id"]
  end

  test "login, create hexdocs key and redirect", c do
    conn =
      post(build_conn(), "login", %{
        username: c.user.username,
        password: "password",
        hexdocs: c.organization.name,
        return: "/my_package/index.html"
      })

    url = "http://#{c.organization.name}.localhost:5002/my_package/index.html?key="
    url_size = byte_size(url)
    assert <<^url::binary-size(url_size), key::binary>> = redirected_to(conn)

    assert {:ok, %{key: key}} = Auth.key_auth(key, [])
    assert key.revoke_at
    refute key.public
    assert hd(key.permissions).domain == "docs"
    assert hd(key.permissions).resource == c.organization.name

    assert get_session(conn, "user_id") == c.user.id
    assert last_session().data["user_id"] == c.user.id
  end

  test "already logged in, create hexdocs key and redirect", c do
    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn =
      conn
      |> recycle()
      |> post("login", %{
        username: c.user.username,
        password: "password",
        hexdocs: c.organization.name
      })

    assert redirected_to(conn) =~ "http://#{c.organization.name}.localhost:5002"
  end

  test "log in, try create hexdocs key for wrong organization", c do
    conn =
      post(build_conn(), "login", %{
        username: c.user.username,
        password: "password",
        hexdocs: "not_my_org"
      })

    assert conn.status == 400
  end

  test "deactivated", c do
    Ecto.Changeset.change(c.user, deactivated_at: DateTime.utc_now()) |> Repo.update!()
    conn = post(build_conn(), "login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"
    conn = get(conn, "/")
    assert response(conn, 400)
  end
end
