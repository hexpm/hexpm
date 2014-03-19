defmodule HexWeb.KeyTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Key

  setup do
    { :ok, _ } = User.create("eric", "eric@mail.com", "eric")
    :ok
  end

  test "create key and get" do
    user = User.get("eric")
    user_id = user.id
    assert { :ok, Key.Entity[] } = Key.create("computer", user)
    assert Key.Entity[user_id: ^user_id] = Key.get("computer", user)
  end

  test "create unique key name" do
    user = User.get("eric")
    assert { :ok, Key.Entity[name: "computer"] } = Key.create("computer", user)
    assert { :ok, Key.Entity[name: "computer-2"] } = Key.create("computer", user)
  end

  test "all user keys" do
    eric = User.get("eric")
    { :ok, jose } = User.create("jose", "jose@mail.com", "jose")
    assert { :ok, Key.Entity[name: "computer"] } = Key.create("computer", eric)
    assert { :ok, Key.Entity[name: "macbook"] } = Key.create("macbook", eric)
    assert { :ok, Key.Entity[name: "macbook"] } = Key.create("macbook", jose)

    assert length(Key.all(eric)) == 2
    assert length(Key.all(jose)) == 1
  end

  test "delete keys" do
    user = User.get("eric")
    assert { :ok, Key.Entity[] } = Key.create("computer", user)
    assert { :ok, Key.Entity[] } = Key.create("macbook", user)
    assert Key.delete(Key.get("computer", user)) == :ok

    assert [Key.Entity[name: "macbook"]] = Key.all(user)
  end
end
