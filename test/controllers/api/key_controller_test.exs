defmodule HexWeb.API.KeyControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.Key
  alias HexWeb.User

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    |> HexWeb.Repo.insert!
    User.create(%{username: "other", email: "other@mail.com", password: "other"}, true)
    |> HexWeb.Repo.insert!
    :ok
  end

  test "create key" do
    body = %{name: "macbook"}
    conn = conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> Base.encode64("eric:eric"))
           |> post("api/keys", Poison.encode!(body))

    user = HexWeb.Repo.get_by!(User, username: "eric")

    assert conn.status == 201
    assert HexWeb.Repo.one(Key.get("macbook", user))

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "key.generate"
    assert %{"name" => "macbook"} = log.params
  end

  test "get key" do
    HexWeb.Repo.get_by!(User, username: "eric")
    |> Key.create(%{name: "macbook"})
    |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/keys/macbook")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "macbook"
    assert body["secret"] == nil
    assert body["url"] =~ "/api/keys/macbook"
  end

  test "all keys" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.create(user, %{name: "macbook"}) |> HexWeb.Repo.insert!
    key = Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 2
    first = hd(body)
    assert first["name"] == "macbook"
    assert first["secret"] == nil
    assert first["url"] =~ "/api/keys/macbook"
  end

  test "delete key" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.create(user, %{name: "macbook"}) |> HexWeb.Repo.insert!
    Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/keys/computer")

    assert conn.status == 204
    assert HexWeb.Repo.one(Key.get("macbook", user))
    refute HexWeb.Repo.one(Key.get("computer", user))

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "key.remove"
    assert %{"name" => "computer"} = log.params
  end

  test "key authorizes" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    key = Key.create(user, %{name: "macbook"}) |> HexWeb.Repo.insert!

    conn = conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 200
    assert length(Poison.decode!(conn.resp_body)) == 1

    conn = conn()
           |> put_req_header("authorization", "wrong")
           |> get("api/keys")

    assert conn.status == 401
  end
end
