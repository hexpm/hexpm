defmodule Hexpm.Web.API.KeyControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Accounts.{AuditLog, Key, KeyPermission}

  setup do
    eric = create_user("eric", "eric@mail.com", "ericeric")
    other = create_user("other", "other@mail.com", "otherother")
    repo = insert(:repository)
    unowned_repo = insert(:repository)
    insert(:repository_user, repository: repo, user: eric)
    {:ok, repo: repo, unowned_repo: unowned_repo, eric: eric, other: other}
  end

  test "create api key", c do
    body = %{name: "macbook"}
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Basic " <> Base.encode64("eric:ericeric"))
      |> post("api/keys", Poison.encode!(body))

    assert conn.status == 201
    key = Hexpm.Repo.one!(Key.get(c.eric, "macbook"))
    assert [%KeyPermission{domain: "api"}] = key.permissions

    log = Hexpm.Repo.one!(AuditLog)
    assert log.actor_id == c.eric.id
    assert log.action == "key.generate"
    assert %{"name" => "macbook"} = log.params
  end

  test "create repo key", c do
    body = %{name: "macbook", permissions: [%{domain: "repository", resource: c.repo.name}]}
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Basic " <> Base.encode64("eric:ericeric"))
    |> post("api/keys", Poison.encode!(body))
    |> json_response(201)

    key = Hexpm.Repo.one!(Key.get(c.eric, "macbook"))
    repo_name = c.repo.name
    assert [%KeyPermission{domain: "repository", resource: ^repo_name}] = key.permissions
  end

  test "create repo key for repository unknown repository is allowed", c do
    body = %{name: "macbook", permissions: [%{domain: "repository", resource: "SOME_UNKNOWN_REPO"}]}
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Basic " <> Base.encode64("eric:ericeric"))
    |> post("api/keys", Poison.encode!(body))
    |> json_response(201)

    key = Hexpm.Repo.one!(Key.get(c.eric, "macbook"))
    assert [%KeyPermission{domain: "repository", resource: "SOME_UNKNOWN_REPO"}] = key.permissions
  end

  test "get key", c do
    c.eric
    |> Key.build(%{name: "macbook"})
    |> Hexpm.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> get("api/keys/macbook")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "macbook"
    assert body["secret"] == nil
    assert body["url"] =~ "/api/keys/macbook"
    assert body["permissions"] == [%{"domain" => "api", "resource" => nil}]
    refute body["authing_key"]
  end

  test "all keys", c do
    Key.build(c.eric, %{name: "macbook"}) |> Hexpm.Repo.insert!
    key = Key.build(c.eric, %{name: "computer"}) |> Hexpm.Repo.insert!

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

  test "delete key", c do
    Key.build(c.eric, %{name: "macbook"}) |> Hexpm.Repo.insert!
    Key.build(c.eric, %{name: "computer"}) |> Hexpm.Repo.insert!

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.eric))
           |> delete("api/keys/computer")

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "computer"
    assert body["revoked_at"]
    assert body["updated_at"]
    assert body["inserted_at"]
    refute body["secret"]
    refute body["authing_key"]
    assert Hexpm.Repo.one(Key.get(c.eric, "macbook"))
    refute Hexpm.Repo.one(Key.get(c.eric, "computer"))

    assert Hexpm.Repo.one(Key.get_revoked(c.eric, "computer"))

    log = Hexpm.Repo.one!(AuditLog)
    assert log.actor_id == c.eric.id
    assert log.action == "key.remove"
    assert %{"name" => "computer"} = log.params
  end

  test "delete current key notifies client", c do
    key = Key.build(c.eric, %{name: "current"}) |> Hexpm.Repo.insert!

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
    assert body["authing_key"]
    refute Hexpm.Repo.one(Key.get(c.eric, "current"))

    assert Hexpm.Repo.one(Key.get_revoked(c.eric, "current"))

    log = Hexpm.Repo.one!(AuditLog)
    assert log.actor_id == c.eric.id
    assert log.action == "key.remove"
    assert %{"name" => "current"} = log.params

    conn = build_conn()
           |> put_req_header("authorization", key.user_secret)
           |> get("api/keys")

    assert conn.status == 401
    body = Poison.decode!(conn.resp_body)
    assert %{"message" => "API key revoked", "status" => 401} == body
  end

  test "delete all keys", c do
    key_a = Key.build(c.eric, %{name: "key_a"}) |> Hexpm.Repo.insert!
    key_b = Key.build(c.eric, %{name: "key_b"}) |> Hexpm.Repo.insert!

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
    assert body["authing_key"]
    refute Hexpm.Repo.one(Key.get(c.eric, "key_a"))
    refute Hexpm.Repo.one(Key.get(c.eric, "key_b"))

    assert Hexpm.Repo.one(Key.get_revoked(c.eric, "key_a"))
    assert Hexpm.Repo.one(Key.get_revoked(c.eric, "key_b"))

    assert [log_a, log_b] =
      AuditLog
      |> Hexpm.Repo.all()
      |> Enum.sort_by(fn (%{params: %{"name" => name}}) -> name end)
    assert log_a.actor_id == c.eric.id
    assert log_a.action == "key.remove"
    key_a_name = key_a.name
    assert %{"name" => ^key_a_name} = log_a.params
    assert log_b.actor_id == c.eric.id
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

  test "key authorizes", c do
    key = Key.build(c.eric, %{name: "macbook"}) |> Hexpm.Repo.insert!

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
