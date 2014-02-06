defmodule ExplexWeb.RouterTest do
  use ExplexWebTest.Case
  import Plug.Test
  alias ExplexWeb.Router
  alias ExplexWeb.User
  alias ExplexWeb.Package

  setup do
    User.create("eric", "eric", "eric")
    :ok
  end

  test "create user" do
    body = [username: "name", email: "email", password: "pass"]
    conn = conn("POST", "/api/beta/user", JSON.encode!(body), headers: [{ "content-type", "application/json" }])
    { _, conn } = Router.call(conn, [])

    assert conn.status == 201
    user = assert User.get("name")
    assert user.email == "email"
  end

  test "create user validates" do
    body = [username: "name", password: "pass"]
    conn = conn("POST", "/api/beta/user", JSON.encode!(body), headers: [{ "content-type", "application/json" }])
    { _, conn } = Router.call(conn, [])

    assert conn.status == 422
    body = JSON.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["email"] == "can't be blank"
    refute User.get("name")
  end

  test "create package" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [name: "ecto", meta: []]
    conn = conn("POST", "/api/beta/package", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    user_id = User.get("eric").id
    assert conn.status == 201
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert package.owner_id == user_id
  end

  test "create package authorizes" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:wrong") }]
    body = [name: "ecto", meta: []]
    conn = conn("POST", "/api/beta/package", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 401
    assert conn.resp_headers["www-authenticate"] == "Basic realm=explex"
  end

  test "create package validates" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [name: "ecto", meta: [links: "invalid"]]
    conn = conn("POST", "/api/beta/package", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 422
    body = JSON.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["meta"]["links"] == "wrong type, expected: dict(string, string)"
  end
end
