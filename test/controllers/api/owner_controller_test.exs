defmodule HexWeb.API.OwnerControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    create_user("jose", "jose@mail.com", "josejose")
    create_user("other", "other@mail.com", "otherother")
    pkg = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> HexWeb.Repo.insert!
    Package.build(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> HexWeb.Repo.insert!
    Release.build(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    :ok
  end

  test "get package owners" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [%{"username" => "eric"}] = body

    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    user = HexWeb.Repo.get_by!(User, username: "jose")
    Package.build_owner(package, user) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [first, second] = body
    assert first["username"] in ["jose", "eric"]
    assert second["username"] in ["jose", "eric"]
  end

  test "get package owners authorizes" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("other"))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 403
  end

  test "check if user is package owner" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners/eric@mail.com")
    assert conn.status == 204

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/packages/postgrex/owners/jose@mail.com")
    assert conn.status == 404
  end

  test "check if user is package owner authorizes" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("other"))
           |> get("api/packages/postgrex/owners/eric@mail.com")
    assert conn.status == 403
  end

  test "add package owner" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    jose = HexWeb.Repo.get_by!(User, username: "jose")

    conn = build_conn()
           |> put_req_header("authorization", key_for(eric))
           |> put("api/packages/postgrex/owners/#{jose.username}")
    assert conn.status == 204

    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    assert [first, second] = assoc(package, :owners) |> HexWeb.Repo.all
    assert first.username in ["jose", "eric"]
    assert second.username in ["jose", "eric"]

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == eric.id
    assert log.action == "owner.add"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params

    {subject, contents} = HexWeb.Mail.Local.read("eric@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been added as an owner to package postgrex."

    {subject, contents} = HexWeb.Mail.Local.read("jose@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been added as an owner to package postgrex."
  end

  test "add unknown user package owner" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    
    conn = build_conn()
           |> put_req_header("authorization", key_for(eric))
           |> put("api/packages/postgrex/owners/UNKNOWN")
    assert conn.status == 404
  end

  test "cannot add same owner twice" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 204

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["errors"]["owner_id"] == "is already owner"
  end

  test "add package owner authorizes" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("other"))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 403
  end

  test "delete package owner" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    jose = HexWeb.Repo.get_by!(User, username: "jose")
    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    Package.build_owner(package, jose) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for(eric))
           |> delete("api/packages/postgrex/owners/#{jose.username}")
    assert conn.status == 204
    assert [%User{username: "eric"}] = assoc(package, :owners) |> HexWeb.Repo.all

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == eric.id
    assert log.action == "owner.remove"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params

    {subject, contents} = HexWeb.Mail.Local.read("eric@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been removed from owners of package postgrex."

    {subject, contents} = HexWeb.Mail.Local.read("jose@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "jose (jose@mail.com) has been removed from owners of package postgrex."
  end

  test "delete package owner authorizes" do
    conn = build_conn()
           |> put_req_header("authorization", key_for("other"))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
  end

  test "not possible to remove last owner of package" do
    package = HexWeb.Repo.get_by!(Package, name: "postgrex")

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
    assert [%User{username: "eric"}] = assoc(package, :owners) |> HexWeb.Repo.all
  end
end
