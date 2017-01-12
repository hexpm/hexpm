defmodule HexWeb.API.OwnerControllerTest do
  # TODO: debug Bamboo.Test race conditions and change back to async: true
  use HexWeb.ConnCase, async: false
  use Bamboo.Test

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    eric = create_user("eric", "eric@mail.com", "ericeric")
    jose = create_user("jose", "jose@mail.com", "josejose")
    other = create_user("other", "other@mail.com", "otherother")
    pkg = Package.build(eric, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> HexWeb.Repo.insert!
    package = Package.build(eric, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> HexWeb.Repo.insert!
    Release.build(pkg, rel_meta(%{version: "0.0.1", app: "postgrex"}), "") |> HexWeb.Repo.insert!

    {:ok, eric: eric, jose: jose, other: other, package: package}
  end

  test "get package owners", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [%{"username" => "eric"}] = body

    Package.build_owner(c.package, c.jose) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> get("api/packages/postgrex/owners")
    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    assert [first, second] = body
    assert first["username"] in ["jose", "eric"]
    assert second["username"] in ["jose", "eric"]
  end

  test "check if user is package owner", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> get("api/packages/postgrex/owners/eric@mail.com")
    assert conn.status == 204

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> get("api/packages/postgrex/owners/jose@mail.com")
    assert conn.status == 404
  end

  test "add package owner", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> put("api/packages/postgrex/owners/#{c.jose.username}")
    assert conn.status == 204

    assert [first, second] = assoc(c.package, :owners) |> HexWeb.Repo.all
    assert first.username in ["jose", "eric"]
    assert second.username in ["jose", "eric"]

    [email] = Bamboo.SentEmail.all
    assert email.subject =~ "Hex.pm"
    assert email.html_body =~ "jose (jose@mail.com) has been added as an owner to package postgrex."
    emails_first = assoc(first, :emails) |> HexWeb.Repo.all
    emails_second = assoc(second, :emails) |> HexWeb.Repo.all

    assert [{first.username, hd(emails_first).email}] in email.to
    assert [{second.username, hd(emails_second).email}] in email.to

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == c.eric.id
    assert log.action == "owner.add"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params
  end

  test "add unknown user package owner", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> put("api/packages/postgrex/owners/UNKNOWN")
    assert conn.status == 404
  end

  test "cannot add same owner twice", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 204

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["errors"]["owner_id"] == "is already owner"
  end

  test "add package owner authorizes", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.other))
           |> put("api/packages/postgrex/owners/jose%40mail.com")
    assert conn.status == 403
  end

  test "delete package owner", c do
    Package.build_owner(c.package, c.jose) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> delete("api/packages/postgrex/owners/#{c.jose.username}")
    assert conn.status == 204
    assert [%User{username: "eric"}] = assoc(c.package, :owners) |> HexWeb.Repo.all

    [email] = Bamboo.SentEmail.all
    assert email.subject =~ "Hex.pm"
    assert email.html_body =~ "jose (jose@mail.com) has been removed from owners of package postgrex."

    eric_emails = assoc(c.eric, :emails) |> HexWeb.Repo.all
    jose_emails = assoc(c.jose, :emails) |> HexWeb.Repo.all

    assert [{c.eric.username, hd(eric_emails).email}] in email.to
    assert [{c.jose.username, hd(jose_emails).email}] in email.to

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == c.eric.id
    assert log.action == "owner.remove"
    assert %{"package" => %{"name" => "postgrex"}, "user" => %{"username" => "jose"}} = log.params
  end

  test "delete package owner authorizes", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.other))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
  end

  test "not possible to remove last owner of package", c do
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> delete("api/packages/postgrex/owners/eric%40mail.com")
    assert conn.status == 403
    assert [%User{username: "eric"}] = assoc(c.package, :owners) |> HexWeb.Repo.all
  end
end
