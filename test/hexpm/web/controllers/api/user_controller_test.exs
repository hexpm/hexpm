defmodule Hexpm.Web.API.UserControllerTest do
  # TODO: debug Bamboo.Test race conditions and change back to async: true
  use Hexpm.ConnCase, async: false

  alias Hexpm.Accounts.User

  defp publish_package(user) do
    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    body = create_tar(meta, [])

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/ecto/releases", body)
  end

  describe "POST /api/users" do
    test "create user" do
      params = %{username: Fake.sequence(:username), email: Fake.sequence(:email), password: "passpass"}
      conn = json_post(build_conn(), "api/users", params)
      assert json_response(conn, 201)["url"] =~ "/api/users/#{params.username}"

      user = Hexpm.Repo.get_by!(User, username: params.username) |> Hexpm.Repo.preload(:emails)
      assert List.first(user.emails).email == params.email
    end

    test "create user sends mails and requires confirmation" do
      params = %{username: Fake.sequence(:username), email: Fake.sequence(:email), password: "passpass"}
      conn = json_post(build_conn(), "api/users", params)

      assert conn.status == 201
      user = Hexpm.Repo.get_by!(User, username: params.username) |> Hexpm.Repo.preload(:emails)
      user_email = List.first(user.emails)

      [email] = Bamboo.SentEmail.all
      assert email.subject =~ "Hex.pm"
      assert email.html_body =~ "email/verify?username=#{params.username}&email=#{URI.encode_www_form(user_email.email)}&key=#{user_email.verification_key}"

      conn = publish_package(user)
      assert json_response(conn, 403)["message"] == "email not verified"

      conn = get(build_conn(), "email/verify?username=#{params.username}&email=#{URI.encode_www_form(user_email.email)}&key=#{user_email.verification_key}")
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "verified"

      conn = publish_package(user)
      assert conn.status == 201
    end

    test "create user validates" do
      params = %{username: Fake.sequence(:username), password: "passpass"}
      conn = json_post(build_conn(), "api/users", params)

      result = json_response(conn, 422)
      assert result["message"] == "Validation error(s)"
      assert result["errors"]["emails"] == "can't be blank"
      refute Hexpm.Repo.get_by(User, username: params.username)
    end
  end

  describe "GET /api/users/:name" do
    test "get user" do
      user = insert(:user)
      conn = get(build_conn(), "api/users/#{user.username}")

      body = json_response(conn, 200)
      assert body["username"] == user.username
      assert body["email"] == hd(user.emails).email
      refute body["emails"]
      refute body["password"]

      conn = get(build_conn(), "api/users/bad")
      assert conn.status == 404
    end
  end

  describe "POST /api/users/:name/reset" do
    test "email is sent with reset_token when password is reset" do
      user = insert(:user)
      # initiate reset request
      conn = post(build_conn(), "api/users/#{user.username}/reset", %{})
      assert conn.status == 204

      # check email was sent with correct token
      user = Hexpm.Repo.get_by!(User, username: user.username) |> Hexpm.Repo.preload(:emails)

      [email] = Bamboo.SentEmail.all
      assert email.subject =~ "Hex.pm"
      assert email.html_body =~ "#{user.reset_key}"

      # check reset will succeed
      assert User.password_reset?(user, user.reset_key) == true
    end
  end

  describe "GET /api/users/:name/test" do
    test "test auth" do
      user = insert(:user)

      conn = build_conn()
             |> put_req_header("authorization", key_for(user))
             |> get("api/users/#{user.username}/test")

      body = json_response(conn, 200)
      assert body["username"] == user.username

      conn = build_conn()
             |> put_req_header("authorization", "badkey")
             |> get("api/users/#{user.username}/test")

      assert conn.status == 401
    end
  end

  # TODO
  # NOTE: Also test for website sign up controller
  # test "recreate unconfirmed user" do
  #   # first
  #   body = %{username: "name", email: "email@mail.com", password: "passpass"}
  #   conn = build_conn()
  #          |> put_req_header("content-type", "application/json")
  #          |> post("api/users", Poison.encode!(body))
  #
  #   assert json_response(conn, 201)["url"] =~ "/api/users/name"
  #
  #   user = Hexpm.Repo.get_by!(User, username: "name")
  #   assert user.email == "email@mail.com"
  #
  #   # recreate
  #   body = %{username: "name", email: "other_email@mail.com", password: "other_pass"}
  #   conn = build_conn()
  #          |> put_req_header("content-type", "application/json")
  #          |> post("api/users", Poison.encode!(body))
  #
  #   assert json_response(conn, 201)["url"] =~ "/api/users/name"
  #
  #   user = Hexpm.Repo.get_by!(User, username: "name")
  #   assert user.email == "other_email@mail.com"
  # end
end
