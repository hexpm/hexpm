defmodule HexWeb.KeyTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.User
  alias HexWeb.Key

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "ericeric"}, true)
      |> HexWeb.Repo.insert!

    {:ok, user: user}
  end

  test "create key and get", %{user: user} do
    Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert HexWeb.Repo.one!(Key.get(user, "computer")).user_id == user.id
  end

  test "create unique key name", %{user: user} do
    assert %Key{name: "computer"}   = Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert %Key{name: "computer-2"} = Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!
  end

  test "all user keys", %{user: eric} do
    jose = User.build(%{username: "jose", email: "jose@mail.com", password: "josejose"}, true) |> HexWeb.Repo.insert!

    assert %Key{name: "computer"} = Key.build(eric, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert %Key{name: "macbook"}  = Key.build(eric, %{name: "macbook"}) |> HexWeb.Repo.insert!
    assert %Key{name: "macbook"}  = Key.build(jose, %{name: "macbook"}) |> HexWeb.Repo.insert!

    assert (Key.all(eric) |> HexWeb.Repo.all |> length) == 2
    assert (Key.all(jose) |> HexWeb.Repo.all |> length) == 1
  end

  test "delete keys", %{user: user} do
    Key.build(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    Key.build(user, %{name: "macbook"})  |> HexWeb.Repo.insert!

    Key.get(user, "computer") |> HexWeb.Repo.delete_all
    assert [%Key{name: "macbook"}] = Key.all(user) |> HexWeb.Repo.all
  end
end
