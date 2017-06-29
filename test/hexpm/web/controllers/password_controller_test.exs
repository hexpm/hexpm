defmodule Hexpm.Web.PasswordControllerTest do
  use Hexpm.ConnCase
  alias Hexpm.Accounts.{Auth, Session, User}
  alias Hexpm.Repo

  setup do
    user = insert(:user, password: Auth.gen_password("hunter42"))
    %{user: user}
  end

  describe "GET /password/new" do
    test "show select new password redirect" do
      conn = get(build_conn(), "password/new", %{"username" => "username", "key" => "RESET_KEY"})

      assert redirected_to(conn) == "/password/new"
      assert get_session(conn, "reset_username") == "username"
      assert get_session(conn, "reset_key") == "RESET_KEY"
    end

    test "show select new password" do
      conn = build_conn()
             |> Plug.Test.init_test_session(%{"reset_username" => "username", "reset_key" => "RESET_KEY"})
             |> get("password/new")

      assert conn.status == 200
      assert conn.resp_body =~ "Choose a new password"
      assert conn.resp_body =~ "RESET_KEY"
    end
  end

  describe "POST /password/new" do
    test "submit new password", c do
      username = c.user.username
      assert {:ok, {%User{username: ^username}, _, _}} = Auth.password_auth(username, "hunter42")
      Repo.insert!(Session.build(%{"user_id" => c.user.id}))
      Repo.insert!(Session.build(%{"user_id" => c.user.id}))

      # initiate password reset (usually done via api)
      user = User.init_password_reset(c.user) |> Repo.update!

      # chose new password (using token) to `abcd1234`
      conn =
        build_conn()
        |> test_login(user)
        |> post("password/new", %{"user" => %{"username" => user.username, "key" => user.reset_key, "password" => "abcd1234"}})
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "password has been changed"
      refute get_session(conn, "user_id")

      # check new password will work
      assert {:ok, {%User{username: ^username}, _, _}} = Auth.password_auth(username, "abcd1234")
      refute last_session().data["user_id"]
    end
  end
end
