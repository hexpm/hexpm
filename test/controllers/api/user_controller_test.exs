defmodule HexWeb.API.UserControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
      |> HexWeb.Repo.insert!

    %{user: user}
  end

  test "create user" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/users/name"

    user = HexWeb.Repo.get_by!(User, username: "name")
    assert user.email == "email@mail.com"
  end

  test "create user sends mails and requires confirmation" do
    body = %{username: "name", email: "create_user@mail.com", password: "pass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 201
    user = HexWeb.Repo.get_by!(User, username: "name")

    {subject, contents} = HexWeb.Email.Local.read("create_user@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "confirm?username=name&key=" <> user.confirmation_key

    policies_href = ~s(http://localhost:4001/policies)
    policies_link = ~s(<a href="#{policies_href}">#{policies_href}</a>)
    assert contents =~ ~s(all of our policies found at #{policies_link})

    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    body = create_tar(meta, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(user))
           |> post("api/packages/ecto/releases", body)

    assert conn.status == 403
    assert conn.resp_body =~ "account unconfirmed"

    conn = get(build_conn(), "confirm?username=name&key=" <> user.confirmation_key)
    assert conn.status == 200
    assert conn.resp_body =~ "Email confirmed"

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(user))
           |> post("api/packages/ecto/releases", body)

    assert conn.status == 201

    {subject, contents} = HexWeb.Email.Local.read("create_user@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "confirmed"
  end

  test "email is sent with reset_token when password is reset", c do
    # initiate reset request
    conn = post(build_conn(), "api/users/#{c.user.username}/reset", %{})
    assert conn.status == 204

    # check email was sent with correct token
    user = HexWeb.Repo.get_by!(User, username: c.user.username)
    {subject, contents} = HexWeb.Email.Local.read(c.user.email)
    assert subject =~ "Hex.pm"
    assert contents =~ "#{user.reset_key}"

    # check reset will succeed
    assert User.reset?(user, user.reset_key) == true
  end

  test "create user validates" do
    body = %{username: "name", password: "pass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert body["errors"]["email"] == "can't be blank"
    refute HexWeb.Repo.get_by(User, username: "name")
  end

  test "get user" do
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/users/eric")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["username"] == "eric"
    assert body["email"] == "eric@mail.com"
    refute body["password"]

    conn = get build_conn(), "api/users/eric"
    assert conn.status == 401
  end

  test "recreate unconfirmed user" do
    # first
    body = %{username: "name", email: "email@mail.com", password: "pass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/users/name"

    user = HexWeb.Repo.get_by!(User, username: "name")
    assert user.email == "email@mail.com"

    # recreate
    body = %{username: "name", email: "other_email@mail.com", password: "other_pass"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> post("api/users", Poison.encode!(body))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/users/name"

    user = HexWeb.Repo.get_by!(User, username: "name")
    assert user.email == "other_email@mail.com"
  end
end
