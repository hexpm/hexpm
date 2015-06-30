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

  @port Application.get_env(:hex_web, :port)

  setup do
    User.create(%{username: "other", email: "other@mail.com", password: "other"}, true)
    User.create(%{username: "jose", email: "jose@mail.com", password: "jose"}, true)
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, _}    = Package.create(user, pkg_meta(%{name: "postgrex"}))
    {:ok, pkg}  = Package.create(user, pkg_meta(%{name: "decimal"}))
    {:ok, rel}  = Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal", requirements: %{postgrex: "0.0.1"}}), "")

    %{rel | has_docs: true} |> HexWeb.Repo.update
    :ok
  end

  test "create user" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
    conn = conn("POST", "/api/users", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/users/name"

    user = User.get(username: "name")
    assert user.email == "email@mail.com"
  end

  test "create user sends mails and requires confirmation" do
    body = %{username: "name", email: "create_user@mail.com", password: "pass"}
    conn = conn("POST", "/api/users", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
    Router.call(conn, [])

    user = User.get(username: "name")

    {subject, contents} = HexWeb.Email.Local.read("create_user@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "confirm?username=name&key=" <> user.confirmation_key

    {:ok, key} = Key.create(user, %{name: "macbook"})
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", key.user_secret)
    conn = Router.call(conn, [])
    assert conn.status == 403
    assert conn.resp_body =~ "Account Unconfirmed"

    conn = conn("GET", "/confirm?username=name&key=" <> user.confirmation_key)
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert conn.resp_body =~ "Account confirmed"

    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", key.user_secret)
    conn = Router.call(conn, [])
    assert conn.status == 201

    {subject, contents} = HexWeb.Email.Local.read("create_user@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "confirmed"
  end

  test "create user validates" do
    body = %{username: "name", password: "pass"}
    conn = conn("POST", "/api/users", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
    conn = Router.call(conn, [])

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["email"] == "can't be blank"
    refute User.get(username: "name")
  end

  test "create package with key auth" do
    user = User.get(username: "eric")
    {:ok, key} = Key.create(user, %{name: "macbook"})

    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", key.user_secret)
    conn = Router.call(conn, [])

    assert conn.status == 201
  end

  test "create package key auth" do
    body = %{meta: %{}}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/packages/ecto"

    user_id = User.get(username: "eric").id
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert [%User{id: ^user_id}] = Package.owners(package)
  end

  test "update package" do
    Package.create(User.get(username: "eric"), pkg_meta(%{name: "ecto"}))

    body = %{meta: %{description: "awesomeness"}}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/packages/ecto"

    assert Package.get("ecto").meta["description"] == "awesomeness"
  end

  test "create package authorizes" do
    body = %{}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:WRONG"))
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "update package authorizes" do
    Package.create(User.get(username: "eric"), pkg_meta(%{name: "ecto"}))

    body = %{}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create package validates" do
    body = %{meta: %{links: "invalid"}}
    conn = conn("PUT", "/api/packages/ecto", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation failed"
    assert body["errors"]["meta"]["links"] == "expected type dict(string, string)"
  end

  test "create releases" do
    body = create_tar(%{name: :postgrex, app: "not_postgrex", version: "0.0.1"}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["meta"]["app"] == "not_postgrex"
    assert body["url"] == "http://localhost:#{@port}/api/packages/postgrex/releases/0.0.1"

    body = create_tar(%{name: :postgrex, version: "0.0.2"}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 201

    postgrex = Package.get("postgrex")
    postgrex_id = postgrex.id
    assert [ %Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 2}},
             %Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 1}} ] =
           Release.all(postgrex)

    Release.get(postgrex, "0.0.1")
  end

  test "create release also creates package" do
    refute Package.get("phoenix")

    body = create_tar(%{name: :phoenix, app: "phoenix", version: "1.0.0"}, [])
    conn = conn("POST", "/api/packages/phoenix/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    assert %Package{name: "phoenix"} = Package.get("phoenix")
  end

  test "update release" do
    body = create_tar(%{name: :postgrex, version: "0.0.1"}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    postgrex = Package.get("postgrex")
    release = Release.get(postgrex, "0.0.1")
    assert release

    release = put_in(release.inserted_at.year, 2000)
    HexWeb.Repo.update(release)

    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only modify a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)
  end

  test "delete release" do
    body = create_tar(%{name: :postgrex, version: "0.0.1"}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    postgrex = Package.get("postgrex")
    release =  Release.get(postgrex, "0.0.1")
    release = put_in(release.inserted_at.year, 2000)
    HexWeb.Repo.update(release)

    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only modify a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)

    release = put_in(release.inserted_at.year, 2030)
    HexWeb.Repo.update(release)

    conn = conn("DELETE", "/api/packages/postgrex/releases/0.0.1")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    postgrex = Package.get("postgrex")
    release =  Release.get(postgrex, "0.0.1")
    refute release
  end

  test "create release authorizes" do
    body = create_tar(%{name: :postgrex, version: "0.0.1"}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create releases with requirements" do
    reqs = %{decimal: %{requirement: "~> 0.0.1", app: "not_decimal"}}
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["requirements"] == %{"decimal" => %{"app" => "not_decimal", "optional" => false, "requirement" => "~> 0.0.1"}}

    postgrex = Package.get("postgrex")
    assert [{"decimal", "not_decimal", "~> 0.0.1", false}] = Release.get(postgrex, "0.0.1").requirements
  end

  test "create release updates registry" do
    path = "tmp/registry.ets"
    RegistryBuilder.rebuild

    File.touch!(path, {{2000,1,1,},{1,1,1}})

    reqs = %{decimal: %{requirement: "~> 0.0.1"}}
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body)
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    refute %File.Stat{mtime: {{2000,1,1,},{1,1,1}}} = File.stat!(path)
  end

  test "create key" do
    body = %{name: "macbook"}
    conn = conn("POST", "/api/keys", Poison.encode!(body))
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    assert Key.get("macbook", User.get(username: "eric"))
  end

  test "get key" do
    Key.create(User.get(username: "eric"), %{name: "macbook"})

    conn = conn("GET", "/api/keys/macbook")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "macbook"
    assert body["secret"] == nil
    assert body["url"] == "http://localhost:#{@port}/api/keys/macbook"
  end

  test "all keys" do
    user = User.get(username: "eric")
    Key.create(user, %{name: "macbook"})
    Key.create(user, %{name: "computer"})

    conn = conn("GET", "/api/keys")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert Dict.size(body) == 2
    first = hd(body)
    assert first["name"] == "macbook"
    assert first["secret"] == nil
    assert first["url"] == "http://localhost:#{@port}/api/keys/macbook"
  end

  test "delete key" do
    user = User.get(username: "eric")
    Key.create(user, %{name: "macbook"})
    Key.create(user, %{name: "computer"})

    conn = conn("DELETE", "/api/keys/computer")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert Key.get("macbook", user)
    refute Key.get("computer", user)
  end

  test "key authorizes" do
    user = User.get(username: "eric")
    Key.create(user, %{name: "macbook"})

    conn = conn("GET", "/api/keys")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    assert Dict.size(Poison.decode!(conn.resp_body)) == 0

    conn = conn("GET", "/api/keys")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:WRONG"))
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "get user" do
    conn = conn("GET", "/api/users/eric")
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert body["username"] == "eric"
    assert body["email"] == "eric@mail.com"
    refute body["password"]

    conn = conn("GET", "/api/users/eric")
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "elixir media response" do
    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex+elixir")
    conn = Router.call(conn, [])

    assert conn.status == 200
    {body, []} = Code.eval_string(conn.resp_body)
    assert body["name"] == "postgrex"
  end

  test "elixir media request" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
           |> HexWeb.API.ElixirFormat.encode
    conn = conn("POST", "/api/users", body)
           |> put_req_header("content-type", "application/vnd.hex+elixir")
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/users/name"

    user = assert User.get(username: "name")
    assert user.email == "email@mail.com"
  end

  test "erlang media response" do
    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex+erlang")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = :erlang.binary_to_term(conn.resp_body)
    assert body["name"] == "postgrex"
  end

  test "erlang media request" do
    body = %{username: "name", email: "email@mail.com", password: "pass"}
           |> HexWeb.API.ErlangFormat.encode

    conn = conn("POST", "/api/users", body)
           |> put_req_header("content-type", "application/vnd.hex+erlang")
    conn = Router.call(conn, [])

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/users/name"

    user = assert User.get(username: "name")
    assert user.email == "email@mail.com"
  end

  test "get package" do
    conn = conn("GET", "/api/packages/decimal")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "decimal"

    release = List.first(body["releases"])
    assert release["url"] == "http://localhost:#{@port}/api/packages/decimal/releases/0.0.1"
    assert release["version"] == "0.0.1"
  end

  test "get release" do
    conn = conn("GET", "/api/packages/decimal/releases/0.0.1")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["url"] == "http://localhost:#{@port}/api/packages/decimal/releases/0.0.1"
    assert body["version"] == "0.0.1"
  end

  test "accepted formats" do
    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/xml")
    conn = Router.call(conn, [])
    assert conn.status == 415

    conn = conn("GET", "/api/WRONGURL")
           |> put_req_header("accept", "application/xml")
    conn = Router.call(conn, [])
    assert conn.status == 404

    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/json")
    conn = Router.call(conn, [])
    assert conn.status == 200
    Poison.decode!(conn.resp_body)

    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex")
    conn = Router.call(conn, [])
    assert conn.status == 200
    Poison.decode!(conn.resp_body)

    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex+json")
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert get_resp_header(conn, "x-hex-media-type") == ["hex.beta"]
    Poison.decode!(conn.resp_body)

    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex.vUNSUPPORTED+json")
    conn = Router.call(conn, [])
    assert conn.status == 415

    conn = conn("GET", "/api/packages/postgrex")
           |> put_req_header("accept", "application/vnd.hex.beta")
    conn = Router.call(conn, [])
    assert conn.status == 200
    assert get_resp_header(conn, "x-hex-media-type") == ["hex.beta"]
    Poison.decode!(conn.resp_body)
  end

  test "fetch many packages" do
    conn = conn("GET", "/api/packages")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert Dict.size(body) == 2

    conn = conn("GET", "/api/packages?search=post")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert Dict.size(body) == 1

    conn = conn("GET", "/api/packages?page=1")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert Dict.size(body) == 2

    conn = conn("GET", "/api/packages?page=2")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert Dict.size(body) == 0
  end

  test "fetch sort order" do
    {year, month, day} = :erlang.date
    {:ok, future} = Ecto.Date.load({year + 1, month, day})

    postgrex = Package.get("postgrex")
    postgrex = %{postgrex | updated_at: Ecto.DateTime.from_date(future)}
    HexWeb.Repo.update(postgrex)

    decimal = Package.get("decimal")
    decimal = %{decimal | inserted_at: Ecto.DateTime.from_date(future)}
    HexWeb.Repo.update(decimal)

    conn = conn("GET", "/api/packages?sort=updated_at")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "postgrex"

    conn = conn("GET", "/api/packages?sort=inserted_at")
    conn = Router.call(conn, [])

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "decimal"
  end

  test "get package owners" do
    conn = conn("GET", "/api/packages/postgrex/owners")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [%{"username" => "eric"}] = body

    package = Package.get("postgrex")
    user = User.get(username: "jose")
    Package.add_owner(package, user)

    conn = conn("GET", "/api/packages/postgrex/owners")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [first, second] = body
    assert first["username"] in ["jose", "eric"]
    assert second["username"] in ["jose", "eric"]
  end

  test "get package owners authorizes" do
    conn = conn("GET", "/api/packages/postgrex/owners")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "check if user is package owner" do
    conn = conn("GET", "/api/packages/postgrex/owners/eric@mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    conn = conn("GET", "/api/packages/postgrex/owners/jose@mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 404
  end

  test "check if user is package owner authorizes" do
    conn = conn("GET", "/api/packages/postgrex/owners/eric@mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "add package owner" do
    conn = conn("PUT", "/api/packages/postgrex/owners/jose%40mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    package = Package.get("postgrex")
    assert [first, second] = Package.owners(package)
    assert first.username in ["jose", "eric"]
    assert second.username in ["jose", "eric"]
  end

  test "add package owner authorizes" do
    conn = conn("PUT", "/api/packages/postgrex/owners/jose%40mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  test "delete package owner" do
    package = Package.get("postgrex")
    user = User.get(username: "jose")
    Package.add_owner(package, user)

    conn = conn("DELETE", "/api/packages/postgrex/owners/jose%40mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert [%User{username: "eric"}] = Package.owners(package)

    conn = conn("DELETE", "/api/packages/postgrex/owners/jose%40mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    assert [%User{username: "eric"}] = Package.owners(package)
  end

  test "delete package owner authorizes" do
    conn = conn("DELETE", "/api/packages/postgrex/owners/eric%40mail.com")
           |> put_req_header("authorization", "Basic " <> :base64.encode("other:other"))
    conn = Router.call(conn, [])
    assert conn.status == 401
  end

  @tag :integration
  test "integration release docs" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end
    :inets.start

    user           = User.get(username: "eric")
    {:ok, phoenix} = Package.create(user, pkg_meta(%{name: "phoenix"}))
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.2", app: "phoenix"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn("POST", "/api/packages/phoenix/releases/0.0.1/docs", body)
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201
    assert Release.get(phoenix, "0.0.1").has_docs

    url = HexWeb.Util.url("api/packages/phoenix/releases/0.0.1/docs") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], body_format: :binary)
    assert {{_version, 200, _reason}, _headers, ^body} = response

    url = HexWeb.Util.url("docs/phoenix/index.html") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], body_format: :binary)
    assert {{_version, 200, _reason}, _headers, "HEYO"} = response

    url = HexWeb.Util.url("docs/phoenix/0.0.1/index.html") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], body_format: :binary)
    assert {{_version, 200, _reason}, _headers, "HEYO"} = response

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "NOPE"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn("POST", "/api/packages/phoenix/releases/0.0.2/docs", body)
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201

    url = HexWeb.Util.url("docs/phoenix/index.html") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], body_format: :binary)
    assert {{_version, 200, _reason}, _headers, "NOPE"} = response

    url = HexWeb.Util.url("docs/phoenix/0.0.1/index.html") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], body_format: :binary)
    assert {{_version, 200, _reason}, _headers, "HEYO"} = response
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  @tag :integration
  test "delete release with docs" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end
    :inets.start

    user        = User.get(username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn("POST", "/api/packages/ecto/releases/0.0.1/docs", body)
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 201
    assert Release.get(ecto, "0.0.1").has_docs

    conn = conn("DELETE", "/api/packages/ecto/releases/0.0.1")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 204

    # Check release was deleted
    refute Release.get(ecto, "0.0.1")

    # Check docs were deleted
    url = HexWeb.Util.url("api/packages/ecto/releases/0.0.1/docs") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], [])
    assert {{_version, code, _reason}, _headers, _body} = response
    assert code in 400..499

    url = HexWeb.Util.url("docs/ecto/0.0.1/index.html") |> String.to_char_list
    assert {:ok, response} = :httpc.request(:get, {url, []}, [], [])
    assert {{_version, code, _reason}, _headers, _body} = response
    assert code in 400..499
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  @tag :integration
  test "dont allow version directories in docs" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end
    :inets.start

    user        = User.get(username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'1.2.3', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn("POST", "/api/packages/ecto/releases/0.0.1/docs", body)
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
    conn = Router.call(conn, [])
    assert conn.status == 422
    assert %{"errors" => %{"tar" => "directory name not allowed to match a semver version"}} =
           Poison.decode!(conn.resp_body)
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end
end
