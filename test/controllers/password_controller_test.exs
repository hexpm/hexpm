defmodule HexWeb.PasswordControllerTest do
  use HexWeb.ConnCase, async: true
  alias HexWeb.Auth
  alias HexWeb.User
  alias HexWeb.Users

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42")}
  end

  test "show select new password redirect" do
    conn = get(build_conn(), "password/new", %{"username" => "username", "key" => "RESET_KEY"})

    assert redirected_to(conn) == "/password/new"
    assert conn.resp_cookies["reset_username"][:value] == "username"
    assert conn.resp_cookies["reset_key"][:value] == "RESET_KEY"
  end

  test "show select new password" do
    conn = build_conn()
           |> put_req_cookie("reset_username", "username")
           |> put_req_cookie("reset_key", "RESET_KEY")
           |> get("password/new")

    assert conn.status == 200
    assert conn.resp_body =~ "Choose a new password"
    assert conn.resp_body =~ "RESET_KEY"
  end

  test "submit new password", c do
    assert {:ok, {%User{username: "eric"}, _, _}} = Auth.password_auth("eric", "hunter42")

    # initiate password reset (usually done via api)
    user = User.init_password_reset(c.user) |> HexWeb.Repo.update!
    user = Users.sign_in(user)

    # chose new password (using token) to `abcd1234`
    conn = post(build_conn(), "password/new", %{"user" => %{"username" => user.username, "key" => user.reset_key, "password" => "abcd1234"}})
    assert redirected_to(conn) == "/"
    assert get_flash(conn, :info) =~ "password has been changed"

    # check new password will work
    assert {:ok, {%User{username: "eric", session_key: nil}, _, _}} = Auth.password_auth("eric", "abcd1234")
  end
end
