defmodule ExplexWeb.RouterTest do
  use ExplexWebTest.Case
  import Plug.Test
  alias ExplexWeb.Router
  alias ExplexWeb.User
  alias ExplexWeb.Package
  alias ExplexWeb.Release
  alias ExplexWeb.Requirement

  setup do
    { :ok, user } = User.create("eric", "eric", "eric")
    { :ok, _ }    = Package.create("postgrex", user, [])
    { :ok, _ }    = Package.create("decimal", user, [])
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
    body = [meta: []]
    conn = conn("PUT", "/api/beta/package/ecto", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    user_id = User.get("eric").id
    assert conn.status == 201
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert package.owner_id == user_id
  end

  test "update package" do
    Package.create("ecto", User.get("eric"), [])

    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [meta: [description: "awesomeness"]]
    conn = conn("PUT", "/api/beta/package/ecto", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 204
    assert Package.get("ecto").meta["description"] == "awesomeness"
  end

  test "create package authorizes" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:wrong") }]
    body = [meta: []]
    conn = conn("PUT", "/api/beta/package/ecto", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 401
    assert conn.resp_headers["www-authenticate"] == "Basic realm=explex"
  end

  test "create package validates" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [meta: [links: "invalid"]]
    conn = conn("PUT", "/api/beta/package/ecto", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 422
    body = JSON.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["meta"]["links"] == "wrong type, expected: dict(string, string)"
  end

  test "create releases" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [version: "0.0.1", requirements: []]
    conn = conn("POST", "/api/beta/package/postgrex/release", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 201

    body = [version: "0.0.2", requirements: []]
    conn = conn("POST", "/api/beta/package/postgrex/release", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 201

    postgrex = Package.get("postgrex")
    postgrex_id = postgrex.id
    assert [ Release.Entity[package_id: ^postgrex_id, version: "0.0.1"],
             Release.Entity[package_id: ^postgrex_id, version: "0.0.2"] ] =
           Release.all(postgrex)
  end

  test "create releases with requirements" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [version: "0.0.1", requirements: [decimal: "~> 0.0.1"]]
    conn = conn("POST", "/api/beta/package/postgrex/release", JSON.encode!(body), headers: headers)
    { _, conn } = Router.call(conn, [])

    assert conn.status == 201

    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")
    decimal_id = decimal.id
    assert [Requirement.Entity[dependency_id: ^decimal_id, requirement: "~> 0.0.1"]] =
           Release.get(postgrex, "0.0.1").requirements.to_list
  end
end
