defmodule HexWeb.API.RouterTest do
  use HexWebTest.Case
  import Plug.Conn
  import Plug.Test
  alias HexWeb.Router
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.API.Key
  alias HexWeb.RegistryBuilder

  setup do
    User.create("other", "other@mail.com", "other")
    User.create("jose", "jose@mail.com", "jose")
    {:ok, user} = User.create("eric", "eric@mail.com", "eric")
    {:ok, _}    = Package.create("postgrex", user, %{})
    {:ok, pkg}  = Package.create("decimal", user, %{})
    {:ok, _}    = Release.create(pkg, "0.0.1", [{"postgrex", "0.0.1"}], "")
    :ok
  end

  test "create user" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
    conn = conn("POST", "/api/users", Jazz.encode!(body), headers: [{"content-type", "application/json"}])
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/users/name"

    user = assert User.get(username: "name")
    assert user.email == "email@mail.com"
  end

  test "create user validates" do
    body = %{username: "name", password: "pass"}
    conn = conn("POST", "/api/users", Jazz.encode!(body), headers: [{"content-type", "application/json"}])
    conn = Router.call(conn, [])

    assert conn.status == 422
    body = Jazz.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["email"] == "can't be blank"
    refute User.get(username: "name")
  end

  test "update user" do
    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("other:other")}]
    body = %{email: "email@mail.com", password: "pass"}
    conn = conn("PATCH", "/api/users/other", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/users/other"
    user = assert User.get(username: "other")
    assert user.email == "email@mail.com"

    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("other:pass")}]
    body = %{username: "foo"}
    conn = conn("PATCH", "/api/users/other", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/users/other"
    assert User.get(username: "other")
    refute User.get(username: "foo")
  end

  test "update user only basic auth" do
    user = User.get(username: "other")
    {:ok, key} = Key.create("macbook", user)

    headers = [ {"content-type", "application/json"},
                {"authorization", key.secret}]
    body = %{email: "email@mail.com", password: "pass"}
    conn = conn("PATCH", "/api/users/other", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "create package with key auth" do
    user = User.get(username: "eric")
    {:ok, key} = Key.create("macbook", user)

    headers = [ {"content-type", "application/json"},
                {"authorization", key.secret}]
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
  end

  test "create package key auth" do
    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/packages/ecto"

    user_id = User.get(username: "eric").id
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert [%User{id: ^user_id}] = Package.owners(package)
  end

  test "update package" do
    Package.create("ecto", User.get(username: "eric"), %{})

    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = %{meta: %{description: "awesomeness"}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/packages/ecto"

    assert Package.get("ecto").meta["description"] == "awesomeness"
  end

  test "create package authorizes" do
    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("eric:WRONG")}]
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "update package authorizes" do
    Package.create("ecto", User.get(username: "eric"), %{})

    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("other:other")}]
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create package validates" do
    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = %{meta: %{links: "invalid"}}
    conn = conn("PUT", "/api/packages/ecto", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 422
    body = Jazz.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["meta"]["links"] == "wrong type, expected: dict(string, string)"
  end

  test "create releases" do
    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/packages/postgrex/releases/0.0.1"

    body = create_tar(%{app: :postgrex, version: "0.0.2", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201

    postgrex = Package.get("postgrex")
    postgrex_id = postgrex.id
    assert [ %Release{package_id: ^postgrex_id, version: "0.0.2"},
             %Release{package_id: ^postgrex_id, version: "0.0.1"} ] =
           Release.all(postgrex)
  end

  test "update release" do
    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    postgrex = Package.get("postgrex")
    assert Release.get(postgrex, "0.0.1")
  end

  test "delete release" do
    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("DELETE", "/api/packages/postgrex/releases/0.0.1", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    postgrex = Package.get("postgrex")
    refute Release.get(postgrex, "0.0.1")
  end

  test "create release authorizes" do
    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("other:other")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create releases with requirements" do
    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{decimal: "~> 0.0.1"}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Jazz.decode!(conn.resp_body)
    assert body["requirements"] == %{"decimal" => %{"optional" => false, "requirement" => "~> 0.0.1"}}

    postgrex = Package.get("postgrex")
    assert [{"decimal", "~> 0.0.1", false}] = Release.get(postgrex, "0.0.1").requirements.all
  end

  test "create release updates registry" do
    path = "tmp/registry.ets"
    {:ok, _} = RegistryBuilder.start_link
    RegistryBuilder.sync_rebuild

    File.touch!(path, {{2000,1,1,},{1,1,1}})
    %File.Stat{mtime: mtime} = File.stat!(path)

    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{decimal: "~> 0.0.1"}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    # async rebuild
    :timer.sleep(100)

    refute %File.Stat{mtime: {{2000,1,1,},{1,1,1}}} = File.stat!(path)
  after
    RegistryBuilder.stop
  end

  test "create key" do
    headers = [ {"content-type", "application/json"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = %{name: "macbook"}
    conn = conn("POST", "/api/keys", Jazz.encode!(body), headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    assert Key.get("macbook", User.get(username: "eric"))
  end

  test "get key" do
    Key.create("macbook", User.get(username: "eric"))

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/keys/macbook", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Jazz.decode!(conn.resp_body)
    assert body["name"] == "macbook"
    assert body["secret"]
    assert body["url"] == "http://localhost:4000/api/keys/macbook"
  end

  test "all keys" do
    user = User.get(username: "eric")
    Key.create("macbook", user)
    Key.create("computer", user)

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/keys", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Jazz.decode!(conn.resp_body)
    assert Dict.size(body) == 2
    first = hd(body)
    assert first["name"] == "macbook"
    assert first["secret"]
    assert first["url"] == "http://localhost:4000/api/keys/macbook"
  end

  test "delete key" do
    user = User.get(username: "eric")
    Key.create("macbook", user)
    Key.create("computer", user)

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("DELETE", "/api/keys/computer", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert Key.get("macbook", user)
    refute Key.get("computer", user)
  end

  test "key authorizes" do
    user = User.get(username: "eric")
    Key.create("macbook", user)

    headers = [ {"authorization", "Basic " <> :base64.encode("other:other")}]
    conn = conn("GET", "/api/keys", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    assert Dict.size(Jazz.decode!(conn.resp_body)) == 0

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:WRONG")}]
    conn = conn("GET", "/api/keys", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "get user" do
    conn = conn("GET", "/api/users/eric")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["username"] == "eric"
    assert body["email"] == "eric@mail.com"
    refute body["password"]
  end

  test "elixir media response" do
    headers = [ {"accept", "application/vnd.hex+elixir"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])

    assert conn.status == 200
    {body, []} = Code.eval_string(conn.resp_body)
    # Remove when API only supports maps
    body = Enum.into(body, %{})
    assert body["username"] == "eric"
    assert body["email"] == "eric@mail.com"
  end

  test "elixir media request" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
           |> HexWeb.API.ElixirFormat.encode
    conn = conn("POST", "/api/users", body, headers: [{"content-type", "application/vnd.hex+elixir"}])
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/users/name"

    user = assert User.get(username: "name")
    assert user.email == "email@mail.com"
  end

  test "get package" do
    conn = conn("GET", "/api/packages/decimal")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["name"] == "decimal"

    release = List.first(body["releases"])
    assert release["url"] == "http://localhost:4000/api/packages/decimal/releases/0.0.1"
    assert release["version"] == "0.0.1"
  end

  test "get release" do
    conn = conn("GET", "/api/packages/decimal/releases/0.0.1")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:4000/api/packages/decimal/releases/0.0.1"
    assert body["version"] == "0.0.1"
  end

  test "accepted formats" do
    headers = [ {"accept", "application/xml"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 415

    headers = [ {"accept", "application/xml"} ]
    conn = conn("GET", "/api/WRONGURL", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 404

    headers = [ {"accept", "application/json"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    Jazz.decode!(conn.resp_body)

    headers = [ {"accept", "application/vnd.hex"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    Jazz.decode!(conn.resp_body)

    headers = [ {"accept", "application/vnd.hex+Jazz"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert get_resp_header(conn, "x-hex-media-type") == ["hex.beta"]
    Jazz.decode!(conn.resp_body)

    headers = [ {"accept", "application/vnd.hex.vUNSUPPORTED+Jazz"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 415

    headers = [ {"accept", "application/vnd.hex.beta"} ]
    conn = conn("GET", "/api/users/eric", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert get_resp_header(conn, "x-hex-media-type") == ["hex.beta"]
    Jazz.decode!(conn.resp_body)
  end

  test "fetch many packages" do
    conn = conn("GET", "/api/packages")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert Dict.size(body) == 2

    conn = conn("GET", "/api/packages?search=post")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert Dict.size(body) == 1

    conn = conn("GET", "/api/packages?page=1")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert Dict.size(body) == 2

    conn = conn("GET", "/api/packages?page=2")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Jazz.decode!(conn.resp_body)
    assert Dict.size(body) == 0
  end

  test "get package owners" do
    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/packages/postgrex/owners", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Jazz.decode!(conn.resp_body)
    assert [%{"username" => "eric"}] = body

    package = Package.get("postgrex")
    user = User.get(username: "jose")
    Package.add_owner(package, user)

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/packages/postgrex/owners", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Jazz.decode!(conn.resp_body)
    assert [%{"username" => "jose"}, %{"username" => "eric"}] = body
  end

  test "get package owners authorizes" do
    headers = [ {"authorization", "Basic " <> :base64.encode("other:other")}]
    conn = conn("GET", "/api/packages/postgrex/owners", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "check if user is package owner" do
    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/packages/postgrex/owners/eric@mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("GET", "/api/packages/postgrex/owners/jose@mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 404
  end

  test "check if user is package owner authorizes" do
    headers = [ {"authorization", "Basic " <> :base64.encode("other:other")}]
    conn = conn("GET", "/api/packages/postgrex/owners/eric@mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "add package owner" do
    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("PUT", "/api/packages/postgrex/owners/jose%40mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    package = Package.get("postgrex")
    assert [%User{username: "jose"}, %User{username: "eric"}] = Package.owners(package)
  end

  test "add package owner authorizes" do
    headers = [ {"authorization", "Basic " <> :base64.encode("other:other")}]
    conn = conn("PUT", "/api/packages/postgrex/owners/jose%40mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "delete package owner" do
    package = Package.get("postgrex")
    user = User.get(username: "jose")
    Package.add_owner(package, user)

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("DELETE", "/api/packages/postgrex/owners/jose%40mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert [%User{username: "eric"}] = Package.owners(package)

    headers = [ {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    conn = conn("DELETE", "/api/packages/postgrex/owners/jose%40mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert [%User{username: "eric"}] = Package.owners(package)
  end

  test "delete package owner authorizes" do
    headers = [ {"authorization", "Basic " <> :base64.encode("other:other")}]
    conn = conn("DELETE", "/api/packages/postgrex/owners/eric%40mail.com", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 401
  end
end
