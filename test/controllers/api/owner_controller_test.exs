defmodule HexWeb.API.OwnerControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    User.create(%{username: "jose", email: "jose@mail.com", password: "jose"}, true) |> HexWeb.Repo.insert!
    User.create(%{username: "other", email: "other@mail.com", password: "other"}, true) |> HexWeb.Repo.insert!
    {:ok, pkg} = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    {:ok, _}   = Package.create(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"}))
    {:ok, _}   = Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    :ok
  end

  test "get package owners" do
    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [%{"username" => "eric"}] = body

    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    user = HexWeb.Repo.get_by!(User, username: "jose")
    Package.create_owner(package, user) |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [first, second] = body
    assert first["username"] in ["jose", "eric"]
    assert second["username"] in ["jose", "eric"]
  end

  test "get package owners authorizes" do
    conn = conn()
           |> put_req_header("authorization", key_for("other"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 403
  end

  test "check if user is package owner" do
    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners/eric@mail.com")
    assert conn.status == 204

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners/jose@mail.com")
    assert conn.status == 404
  end

  test "check if user is package owner authorizes" do
    conn = conn()
           |> put_req_header("authorization", key_for("other"))
           |> get("api/packages/postgrex/owners/eric@mail.com")
    assert conn.status == 403
  end

  test "add package owner" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    jose = HexWeb.Repo.get_by!(User, username: "jose")

    conn = conn()
           |> put_req_header("authorization", key_for(eric))
           |> put("api/packages/postgrex/owners/#{jose.email}")
    assert conn.status == 204

    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    assert [first, second] = assoc(package, :owners) |> HexWeb.Repo.all
    assert first.username in ["jose", "eric"]
    assert second.username in ["jose", "eric"]

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == eric.id
    assert log.action == "owner.add"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params

    {subject, contents} = HexWeb.Email.Local.read("eric@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been added as an owner to package postgrex."

    {subject, contents} = HexWeb.Email.Local.read("jose@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been added as an owner to package postgrex."
  end

  test "cannot add same owner twice" do
    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 204

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["errors"]["owner_id"] == "is already owner"
  end

  test "add package owner authorizes" do
    conn = conn()
           |> put_req_header("authorization", key_for("other"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 403
  end

  test "delete package owner" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    jose = HexWeb.Repo.get_by!(User, username: "jose")
    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    Package.create_owner(package, jose) |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key_for(eric))
           |> delete("api/packages/postgrex/owners/#{jose.email}")
    assert conn.status == 204
    assert [%User{username: "eric"}] = assoc(package, :owners) |> HexWeb.Repo.all

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == eric.id
    assert log.action == "owner.remove"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params

    {subject, contents} = HexWeb.Email.Local.read("eric@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been removed from owners of package postgrex."

    {subject, contents} = HexWeb.Email.Local.read("jose@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been removed from owners of package postgrex."
  end

  test "delete package owner authorizes" do
    conn = conn()
           |> put_req_header("authorization", key_for("other"))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
  end

  test "not possible to remove last owner of package" do
    package = HexWeb.Repo.get_by!(Package, name: "postgrex")

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
    assert [%User{username: "eric"}] = assoc(package, :owners) |> HexWeb.Repo.all
  end
end
