defmodule HexWeb.API.KeyControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Key
  alias HexWeb.User

  setup do
    create_user("eric", "eric@mail.com", "ericeric")
    create_user("other", "other@mail.com", "otherother")
    :ok
  end

  test "create key" do
    body = %{name: "macbook"}
    conn = build_conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> Base.encode64("eric:ericeric"))
           |> post("api/keys", Poison.encode!(body))

    user = HexWeb.Repo.get_by!(User, username: "eric")

    assert conn.status == 201
    assert HexWeb.Repo.one(Key.get(user, "macbook"))

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "key.generate"
    assert %{"name" => "macbook"} = log.params
  end

  test "get key" do
    HexWeb.Repo.get_by!(User, username: "eric")
    |> Key.build(%{name: "macbook"})
    |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> get("api/keys/macbook")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "macbook"
    assert body["secret"] == nil
    assert body["url"] =~ "/api/keys/macbook"
    refute body["authing_key"]
  end

  test "all keys" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.build(user, %{name: "macbook"}) |> HexWeb.Repo.insert!
    key = Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 200
    body = conn.resp_body
      |> Poison.decode!()
      |> Enum.sort_by(fn (%{"name" => name}) -> name end)
    assert length(body) == 2
    [a, b] = body
    assert a["name"] == "computer"
    assert a["secret"] == nil
    assert a["url"] =~ "/api/keys/computer"
    assert a["authing_key"]
    assert b["name"] == "macbook"
    assert b["secret"] == nil
    assert b["url"] =~ "/api/keys/macbook"
    refute b["authing_key"]
  end

  test "delete key" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.build(user, %{name: "macbook"}) |> HexWeb.Repo.insert!
    Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/keys/computer")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "computer"
    assert body["revoked_at"]
    assert body["updated_at"]
    assert body["inserted_at"]
    refute body["secret"]
    refute body["url"]
    refute body["authing_key"]
    assert HexWeb.Repo.one(Key.get(user, "macbook"))
    refute HexWeb.Repo.one(Key.get(user, "computer"))

    assert HexWeb.Repo.one(Key.get_revoked(user, "computer"))

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "key.remove"
    assert %{"name" => "computer"} = log.params
  end

  test "delete current key notifies client" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    key = Key.build(user, %{name: "current"}) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> delete("api/keys/current")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "current"
    assert body["revoked_at"]
    assert body["updated_at"]
    assert body["inserted_at"]
    refute body["secret"]
    refute body["url"]
    assert body["authing_key"]
    refute HexWeb.Repo.one(Key.get(user, "current"))

    assert HexWeb.Repo.one(Key.get_revoked(user, "current"))

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "key.remove"
    assert %{"name" => "current"} = log.params

    conn = build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 401
    body = Poison.decode!(conn.resp_body)
    assert %{"message" => "API key revoked", "status" => 401} == body
  end

  test "delete all keys" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    key_a = Key.build(user, %{name: "key_a"}) |> HexWeb.Repo.insert!
    key_b = Key.build(user, %{name: "key_b"}) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_a.user_secret)
           |> delete("api/keys")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == key_a.name
    assert body["revoked_at"]
    assert body["updated_at"]
    assert body["inserted_at"]
    refute body["secret"]
    refute body["url"]
    assert body["authing_key"]
    refute HexWeb.Repo.one(Key.get(user, "key_a"))
    refute HexWeb.Repo.one(Key.get(user, "key_b"))

    assert HexWeb.Repo.one(Key.get_revoked(user, "key_a"))
    assert HexWeb.Repo.one(Key.get_revoked(user, "key_b"))

    assert [log_a, log_b] =
      HexWeb.AuditLog
      |> HexWeb.Repo.all()
      |> Enum.sort_by(fn (%{params: %{"name" => name}}) -> name end)
    assert log_a.actor_id == user.id
    assert log_a.action == "key.remove"
    key_a_name = key_a.name
    assert %{"name" => ^key_a_name} = log_a.params
    assert log_b.actor_id == user.id
    assert log_b.action == "key.remove"
    key_b_name = key_b.name
    assert %{"name" => ^key_b_name} = log_b.params

    conn = build_conn()
           |> put_req_header("authorization", key_a.user_secret)
           |> get("api/keys")

    assert conn.status == 401
    body = Poison.decode!(conn.resp_body)
    assert %{"message" => "API key revoked", "status" => 401} == body
  end

  test "key authorizes" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    key = Key.build(user, %{name: "macbook"}) |> HexWeb.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 200
    assert length(Poison.decode!(conn.resp_body)) == 1

    conn = build_conn()
           |> put_req_header("authorization", "wrong")
           |> get("api/keys")

    assert conn.status == 401
  end
end
