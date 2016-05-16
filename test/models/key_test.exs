defmodule HexWeb.KeyTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.User
  alias HexWeb.Key

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    |> HexWeb.Repo.insert!
    :ok
  end

  test "create key and get" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert HexWeb.Repo.one!(Key.get("computer", user)).user_id == user.id
  end

  test "create unique key name" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert %Key{name: "computer"}   = Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert %Key{name: "computer-2"} = Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!
  end

  test "all user keys" do
    eric = HexWeb.Repo.get_by!(User, username: "eric")
    jose = User.create(%{username: "jose", email: "jose@mail.com", password: "jose"}, true) |> HexWeb.Repo.insert!

    assert %Key{name: "computer"} = Key.create(eric, %{name: "computer"}) |> HexWeb.Repo.insert!
    assert %Key{name: "macbook"}  = Key.create(eric, %{name: "macbook"}) |> HexWeb.Repo.insert!
    assert %Key{name: "macbook"}  = Key.create(jose, %{name: "macbook"}) |> HexWeb.Repo.insert!

    assert (Key.all(eric) |> HexWeb.Repo.all |> length) == 2
    assert (Key.all(jose) |> HexWeb.Repo.all |> length) == 1
  end

  test "delete keys" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    Key.create(user, %{name: "computer"}) |> HexWeb.Repo.insert!
    Key.create(user, %{name: "macbook"})  |> HexWeb.Repo.insert!

    Key.get("computer", user) |> HexWeb.Repo.delete_all
    assert [%Key{name: "macbook"}] = Key.all(user) |> HexWeb.Repo.all
  end
end
