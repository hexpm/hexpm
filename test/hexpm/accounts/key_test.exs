defmodule Hexpm.Accounts.KeyTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Key

  setup do
    %{user: insert(:user)}
  end

  test "create key and get", %{user: user} do
    Key.build(user, %{name: "computer"}) |> Hexpm.Repo.insert!()
    assert Hexpm.Repo.one!(Key.get(user, "computer")).user_id == user.id
  end

  test "bounds the key name in codepoints", %{user: user} do
    assert %Key{} = Key.build(user, %{name: codepoints_string(255)}) |> Hexpm.Repo.insert!()

    changeset = Key.build(user, %{name: codepoints_string(256)})
    assert errors_on(changeset).name == "should be at most 255 character(s)"
  end

  test "rejects a key whose unique suffix would exceed the name cap", %{user: user} do
    name = String.duplicate("k", 254)
    Key.build(user, %{name: name}) |> Hexpm.Repo.insert!()

    assert {:error, changeset} = Key.build(user, %{name: name}) |> Hexpm.Repo.insert()
    assert errors_on(changeset).name == "should be at most 255 character(s)"
  end

  test "bounds the number of permissions", %{user: user} do
    permissions = List.duplicate(%{domain: "api", resource: "read"}, 1000)
    assert Key.build(user, %{name: "computer", permissions: permissions}).valid?

    permissions = List.duplicate(%{domain: "api", resource: "read"}, 1001)
    changeset = Key.build(user, %{name: "computer", permissions: permissions})
    assert errors_on(changeset).permissions == "should have at most 1000 item(s)"
  end

  test "bounds the permission resource in bytes", %{user: user} do
    permissions = [%{domain: "package", resource: "hexpm/" <> combining_string(506)}]
    changeset = Key.build(user, %{name: "computer", permissions: permissions})

    assert permission_error(changeset).resource == "you do not have access to this package"

    permissions = [%{domain: "package", resource: "hexpm/" <> combining_string(507)}]
    changeset = Key.build(user, %{name: "computer", permissions: permissions})
    assert permission_error(changeset).resource == "should be at most 512 byte(s)"
  end

  defp permission_error(changeset) do
    changeset |> errors_on() |> Map.fetch!(:permissions) |> List.wrap() |> hd()
  end

  test "create unique key name", %{user: user} do
    Key.build(user, %{name: "computer-duplicate"}) |> Hexpm.Repo.insert!()
    Key.build(user, %{name: "computer-2-duplicate"}) |> Hexpm.Repo.insert!()

    assert %Key{name: "computer"} = Key.build(user, %{name: "computer"}) |> Hexpm.Repo.insert!()
    assert %Key{name: "computer-2"} = Key.build(user, %{name: "computer"}) |> Hexpm.Repo.insert!()
    assert %Key{name: "computer-3"} = Key.build(user, %{name: "computer"}) |> Hexpm.Repo.insert!()
  end

  test "all user keys", %{user: user1} do
    user2 = insert(:user)

    assert %Key{name: "computer"} = Key.build(user1, %{name: "computer"}) |> Hexpm.Repo.insert!()
    assert %Key{name: "macbook"} = Key.build(user1, %{name: "macbook"}) |> Hexpm.Repo.insert!()
    assert %Key{name: "macbook"} = Key.build(user2, %{name: "macbook"}) |> Hexpm.Repo.insert!()

    assert Key.all(user1) |> Hexpm.Repo.all() |> length == 2
    assert Key.all(user2) |> Hexpm.Repo.all() |> length == 1
  end

  test "delete keys", %{user: user} do
    Key.build(user, %{name: "computer"}) |> Hexpm.Repo.insert!()
    Key.build(user, %{name: "macbook"}) |> Hexpm.Repo.insert!()

    Key.get(user, "computer") |> Hexpm.Repo.delete_all()
    assert [%Key{name: "macbook"}] = Key.all(user) |> Hexpm.Repo.all()
  end
end
