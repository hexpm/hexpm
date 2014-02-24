defmodule HexWeb.RouterTest do
  use HexWebTest.Case
  import Plug.Test
  alias HexWeb.Router
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    { :ok, user } = User.create("eric", "eric", "eric")
    { :ok, _ }    = Package.create("postgrex", user, [])
    { :ok, pkg }  = Package.create("decimal", user, [])
    { :ok, _ }    = Release.create(pkg, "0.0.1", "url", "ref", [{ "postgrex", "0.0.1" }])
    :ok
  end

  test "create user" do
    body = [username: "name", email: "email", password: "pass"]
    conn = conn("POST", "/api/users", JSON.encode!(body), headers: [{ "content-type", "application/json" }])
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/users/name"

    user = assert User.get("name")
    assert user.email == "email"
  end

  test "create user validates" do
    body = [username: "name", password: "pass"]
    conn = conn("POST", "/api/users", JSON.encode!(body), headers: [{ "content-type", "application/json" }])
    conn = Router.call(conn, [])

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
    conn = conn("PUT", "/api/packages/ecto", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/packages/ecto"

    user_id = User.get("eric").id
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert package.owner_id == user_id
  end

  test "update package" do
    Package.create("ecto", User.get("eric"), [])

    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [meta: [description: "awesomeness"]]
    conn = conn("PUT", "/api/packages/ecto", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/packages/ecto"

    assert Package.get("ecto").meta["description"] == "awesomeness"
  end

  test "create package authorizes" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:wrong") }]
    body = [meta: []]
    conn = conn("PUT", "/api/packages/ecto", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert conn.resp_headers["www-authenticate"] == "Basic realm=hex"
  end

  test "create package validates" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [meta: [links: "invalid"]]
    conn = conn("PUT", "/api/packages/ecto", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 422
    body = JSON.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["meta"]["links"] == "wrong type, expected: dict(string, string)"
  end

  test "create releases" do
    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [git_url: "url", git_ref: "ref", version: "0.0.1", requirements: []]
    conn = conn("POST", "/api/packages/postgrex/releases", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/packages/postgrex/releases/0.0.1"

    body = [git_url: "url", git_ref: "ref", version: "0.0.2", requirements: []]
    conn = conn("POST", "/api/packages/postgrex/releases", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

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
    body = [git_url: "url", git_ref: "ref", version: "0.0.1", requirements: [decimal: "~> 0.0.1"]]
    conn = conn("POST", "/api/packages/postgrex/releases", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = JSON.decode!(conn.resp_body)
    assert body["requirements"] == [{ "decimal", "~> 0.0.1" }]

    postgrex = Package.get("postgrex")
    assert [{ "decimal", "~> 0.0.1" }] = Release.get(postgrex, "0.0.1").requirements.to_list
  end

  test "create release updates registry" do
    { :ok, _ } = RegistryBuilder.start_link
    RegistryBuilder.rebuild
    path = RegistryBuilder.wait_for_build

    File.touch!(path, {{2000,1,1,},{1,1,1}})
    File.Stat[mtime: mtime] = File.stat!(path)

    headers = [ { "content-type", "application/json" },
                { "authorization", "Basic " <> :base64.encode("eric:eric") }]
    body = [git_url: "url", git_ref: "ref", version: "0.0.1", requirements: [decimal: "~> 0.0.1"]]
    conn = conn("POST", "/api/packages/postgrex/releases", JSON.encode!(body), headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    path = RegistryBuilder.wait_for_build
    refute File.Stat[mtime: {{2000,1,1,},{1,1,1}}] = File.stat!(path)
  after
    RegistryBuilder.stop
  end

  test "fetch registry" do
    { :ok, _ } = RegistryBuilder.start_link
    RegistryBuilder.rebuild
    RegistryBuilder.wait_for_build

    conn = conn("GET", "/api/registry")
    conn = Router.call(conn, [])

    assert conn.status == 200
  after
    RegistryBuilder.stop
  end

  test "get user" do
    conn = conn("GET", "/api/users/eric", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert body["username"] == "eric"
    assert body["email"] == "eric"
    refute body["password"]
  end

  test "elixir media response" do
    headers = [ { "accept", "application/vnd.hex+elixir" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    { body, [] } = Code.eval_string(conn.resp_body)
    assert body["username"] == "eric"
    assert body["email"] == "eric"
  end

  test "elixir media request" do
    body = [username: "name", email: "email", password: "pass"]
           |> HexWeb.Router.Util.safe_serialize_elixir
    conn = conn("POST", "/api/users", body, headers: [{ "content-type", "application/vnd.hex+elixir" }])
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/users/name"

    user = assert User.get("name")
    assert user.email == "email"
  end

  test "get package" do
    conn = conn("GET", "/api/packages/decimal", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert body["name"] == "decimal"

    release = List.first(body["releases"])
    assert release["url"] == "http://hex.pm/api/packages/decimal/releases/0.0.1"
    assert release["version"] == "0.0.1"
    assert release["git_url"] == "url"
    assert release["git_ref"] == "ref"
  end

  test "get release" do
    conn = conn("GET", "/api/packages/decimal/releases/0.0.1", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert body["url"] == "http://hex.pm/api/packages/decimal/releases/0.0.1"
    assert body["version"] == "0.0.1"
    assert body["git_url"] == "url"
    assert body["git_ref"] == "ref"
  end

  test "accepted formats" do
    headers = [ { "accept", "application/xml" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 415

    headers = [ { "accept", "application/xml" } ]
    conn = conn("GET", "/api/WRONGURL", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 404

    headers = [ { "accept", "application/json" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    JSON.decode!(conn.resp_body)

    headers = [ { "accept", "application/vnd.hex" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    JSON.decode!(conn.resp_body)

    headers = [ { "accept", "application/vnd.hex+json" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert conn.resp_headers["x-hex-media-type"] == "hex.beta"
    JSON.decode!(conn.resp_body)

    headers = [ { "accept", "application/vnd.hex.vUNSUPPORTED+json" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 415

    headers = [ { "accept", "application/vnd.hex.beta" } ]
    conn = conn("GET", "/api/users/eric", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert conn.resp_headers["x-hex-media-type"] == "hex.beta"
    JSON.decode!(conn.resp_body)
  end

  test "fetch many packages" do
    conn = conn("GET", "/api/packages", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert length(body) == 2

    conn = conn("GET", "/api/packages?search=post", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert length(body) == 1

    conn = conn("GET", "/api/packages?page=1", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert length(body) == 2

    conn = conn("GET", "/api/packages?page=2", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert length(body) == 0
  end

  test "archives" do
    conn = conn("GET", "/archives", [], [])
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert body["dev"]["version"] == "0.0.1-dev"
  end

  test "redirect" do
    url      = HexWeb.Config.url
    app_host = HexWeb.Config.app_host
    use_ssl  = HexWeb.Config.use_ssl

    HexWeb.Config.url("https://hex.pm")
    HexWeb.Config.app_host("some-host.com")
    HexWeb.Config.use_ssl(true)

    try do
      conn = conn("GET", "/foobar", [], []).scheme(:http)
      conn = Router.call(conn, [])
      assert conn.status == 301
      assert conn.resp_headers["location"] == "https://hex.pm"

      conn = conn("GET", "/foobar", [], []).scheme(:https).host("some-host.com")
      conn = Router.call(conn, [])
      assert conn.status == 301
      assert conn.resp_headers["location"] == "https://hex.pm"
    after
      HexWeb.Config.url(url)
      HexWeb.Config.app_host(app_host)
      HexWeb.Config.use_ssl(use_ssl)
    end
  end

  test "forwarded" do
    headers = [ { "x-forwarded-proto", "https" } ]
    conn = conn("GET", "/foobar", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.scheme == :https

    headers = [ { "x-forwarded-port", "12345" } ]
    conn = conn("GET", "/foobar", [], headers: headers)
    conn = Router.call(conn, [])
    assert conn.port == 12345
  end
end
