defmodule HexWeb.API.KeyTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.API.Key

  setup do
    {:ok, _} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    :ok
  end

  test "create key and get" do
    user = User.get(username: "eric")
    user_id = user.id
    assert {:ok, %Key{}} = Key.create(user, %{name: "computer"})
    assert %Key{user_id: ^user_id} = Key.get("computer", user)
  end

  test "create unique key name" do
    user = User.get(username: "eric")
    assert {:ok, %Key{name: "computer"}}   = Key.create(user, %{name: "computer"})
    assert {:ok, %Key{name: "computer-2"}} = Key.create(user, %{name: "computer"})
  end

  test "all user keys" do
    eric = User.get(username: "eric")
    {:ok, jose} = User.create(%{username: "jose", email: "jose@mail.com", password: "jose"}, true)
    assert {:ok, %Key{name: "computer"}} = Key.create(eric, %{name: "computer"})
    assert {:ok, %Key{name: "macbook"}}  = Key.create(eric, %{name: "macbook"})
    assert {:ok, %Key{name: "macbook"}}  = Key.create(jose, %{name: "macbook"})

    assert length(Key.all(eric)) == 2
    assert length(Key.all(jose)) == 1
  end

  test "delete keys" do
    user = User.get(username: "eric")
    assert {:ok, %Key{}} = Key.create(user, %{name: "computer"})
    assert {:ok, %Key{}} = Key.create(user, %{name: "macbook"})
    assert Key.delete(Key.get("computer", user)) == :ok

    assert [%Key{name: "macbook"}] = Key.all(user)
  end
end
