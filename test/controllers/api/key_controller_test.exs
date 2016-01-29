defmodule HexWeb.API.KeyControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.Key
  alias HexWeb.User

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    User.create(%{username: "other", email: "other@mail.com", password: "other"}, true)
    :ok
  end

  test "create key" do
    body = %{name: "macbook"}
    conn = conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("authorization", "Basic " <> :base64.encode("eric:eric"))
           |> post("api/keys", Poison.encode!(body))

    assert conn.status == 201
    assert Key.get("macbook", User.get(username: "eric"))
  end

  test "get key" do
    Key.create(User.get(username: "eric"), %{name: "macbook"})

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
    user = User.get(username: "eric")
    Key.create(user, %{name: "macbook"})
    {:ok, key} = Key.create(user, %{name: "computer"})

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
    user = User.get(username: "eric")
    Key.create(user, %{name: "macbook"})
    Key.create(user, %{name: "computer"})

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/keys/computer")

    assert conn.status == 204
    assert Key.get("macbook", user)
    refute Key.get("computer", user)
  end

  test "key authorizes" do
    user = User.get(username: "eric")
    {:ok, key} = Key.create(user, %{name: "macbook"})

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
