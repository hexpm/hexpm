defmodule HexWeb.API.ReleaseControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, pkg}  = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    {:ok, _}    = Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    :ok
  end

  test "create release" do
    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "api/packages/ecto/releases/1.0.0"

    user_id = User.get(username: "eric").id
    package = assert Package.get("ecto")
    assert package.name == "ecto"
    assert [%User{id: ^user_id}] = Package.owners(package)
  end

  test "update package" do
    Package.create(User.get(username: "eric"), pkg_meta(%{name: "ecto", description: "DSL"}))

    meta = %{name: "ecto", version: "1.0.0", description: "awesomeness"}
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/packages/ecto/releases/1.0.0"

    assert Package.get("ecto").meta["description"] == "awesomeness"
  end

  test "create release authorizes" do
    body = create_tar(%{name: :postgrex, version: "0.0.1"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "wrong")
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "update package authorizes" do
    Package.create(User.get(username: "eric"), pkg_meta(%{name: "ecto", description: "DSL"}))

    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "wrong")
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create package validates" do
    meta = %{name: "ecto", version: "1.0.0", links: "invalid", description: "description"}
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert body["errors"]["meta"]["links"] == "expected type dict(string, string)"
  end

  test "create releases" do
    body = create_tar(%{name: :postgrex, app: "not_postgrex", version: "0.0.1", description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["meta"]["app"] == "not_postgrex"
    assert body["url"] =~ "/api/packages/postgrex/releases/0.0.1"

    body = create_tar(%{name: :postgrex, version: "0.0.2", description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    postgrex = Package.get("postgrex")
    postgrex_id = postgrex.id
    assert [%Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 2}},
            %Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 1}}] =
           Release.all(postgrex)

    Release.get(postgrex, "0.0.1")
  end

  test "create release also creates package" do
    refute Package.get("phoenix")

    body = create_tar(%{name: :phoenix, app: "phoenix", description: "Web framework", version: "1.0.0"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/phoenix/releases", body)

    assert conn.status == 201
    assert %Package{name: "phoenix"} = Package.get("phoenix")
  end

  test "update release" do
    body = create_tar(%{name: :postgrex, version: "0.0.1", description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 200
    postgrex = Package.get("postgrex")
    release = Release.get(postgrex, "0.0.1")
    assert release

    Ecto.Changeset.change(release, inserted_at: %{Ecto.DateTime.utc | year: 2000})
    |> HexWeb.Repo.update!

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only modify a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)
  end

  test "delete release" do
    body = create_tar(%{name: :postgrex, version: "0.0.1", description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    release = Package.get("postgrex") |> Release.get("0.0.1")
    Ecto.Changeset.change(release, inserted_at: %{Ecto.DateTime.utc | year: 2000})
    |> HexWeb.Repo.update!

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only modify a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)

    Ecto.Changeset.change(release, inserted_at: %{Ecto.DateTime.utc | year: 2030})
    |> HexWeb.Repo.update!

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/postgrex/releases/0.0.1")

    assert conn.status == 204
    postgrex = Package.get("postgrex")
    release =  Release.get(postgrex, "0.0.1")
    refute release
  end

  test "create releases with requirements" do
    reqs = %{decimal: %{requirement: "~> 0.0.1", app: "not_decimal"}}
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

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
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    refute File.stat!(path).mtime == {{2000,1,1,},{1,1,1}}
  end

  test "get release" do
    conn = get conn(), "api/packages/decimal/releases/0.0.1"

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/packages/decimal/releases/0.0.1"
    assert body["version"] == "0.0.1"
  end
end
