defmodule Hexpm.Web.API.UserControllerTest do
  # TODO: debug Bamboo.Test race conditions and change back to async: true
  use Hexpm.ConnCase, async: false

  alias Hexpm.Accounts.User

  setup do
    %{user: create_user("eric", "eric@mail.com", "ericeric")}
  end

  test "create user" do
    body = %{username: "name", email: "email@mail.com", password: "passpass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert json_response(conn, 201)["url"] =~ "/api/users/name"

    user = Hexpm.Repo.get_by!(User, username: "name") |> Hexpm.Repo.preload(:emails)
    assert hd(user.emails).email == "email@mail.com"
  end

  test "create user sends mails and requires confirmation" do
    body = %{username: "name", email: "create_user@mail.com", password: "passpass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 201
    user = Hexpm.Repo.get_by!(User, username: "name") |> Hexpm.Repo.preload(:emails)
    user_email = hd(user.emails)

    [email] = Bamboo.SentEmail.all
    assert email.subject =~ "Hex.pm"
    assert email.html_body =~ "email/verify?username=name&email=#{URI.encode_www_form(user_email.email)}&key=#{user_email.verification_key}"

    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    body = create_tar(meta, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(user))
           |> post("api/packages/ecto/releases", body)

    assert json_response(conn, 403)["message"] == "email not verified"

    conn = get(build_conn(), "email/verify?username=name&email=#{URI.encode_www_form(user_email.email)}&key=#{user_email.verification_key}")
    assert redirected_to(conn) == "/"
    assert get_flash(conn, :info) =~ "verified"

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(user))
           |> post("api/packages/ecto/releases", body)

    assert conn.status == 201
  end

  test "email is sent with reset_token when password is reset", c do
    # initiate reset request
    conn = post(build_conn(), "api/users/#{c.user.username}/reset", %{})
    assert conn.status == 204

    # check email was sent with correct token
    user = Hexpm.Repo.get_by!(User, username: c.user.username) |> Hexpm.Repo.preload(:emails)

    [email] = Bamboo.SentEmail.all
    assert email.subject =~ "Hex.pm"
    assert email.html_body =~ "#{user.reset_key}"

    # check reset will succeed
    assert User.password_reset?(user, user.reset_key) == true
  end

  test "create user validates" do
    body = %{username: "name", password: "passpass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    body = json_response(conn, 422)
    assert body["message"] == "Validation error(s)"
    assert body["errors"]["emails"] == "can't be blank"
    refute Hexpm.Repo.get_by(User, username: "name")
  end

  test "get user", c do
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> get("api/users/#{c.user.username}")

    body = json_response(conn, 200)
    assert body["username"] == c.user.username
    assert body["email"] == hd(c.user.emails).email
    refute body["emails"]
    refute body["password"]

    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> get("api/users/bad")

    json_response(conn, 404)
  end

  test "test auth", c do
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", key_for(c.user))
           |> get("api/users/#{c.user.username}/test")

    body = json_response(conn, 200)
    assert body["username"] == c.user.username

    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "badkey")
           |> get("api/users/#{c.user.username}/test")

    json_response(conn, 401)
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
