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
end
