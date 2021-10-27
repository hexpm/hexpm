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

  test "verify_permissions/3" do
    key = build(:key, permissions: [build(:key_permission, domain: "repositories")])
    refute Key.verify_permissions?(key, "api", "read")
    refute Key.verify_permissions?(key, "api", "write")
    assert Key.verify_permissions?(key, "repository", "foo")
    assert Key.verify_permissions?(key, "repositories", nil)

    key =
      build(:key, permissions: [build(:key_permission, domain: "repository", resource: "foo")])

    refute Key.verify_permissions?(key, "api", "read")
    refute Key.verify_permissions?(key, "api", "write")
    assert Key.verify_permissions?(key, "repository", "foo")
    refute Key.verify_permissions?(key, "repository", "bar")
    refute Key.verify_permissions?(key, "repositories", nil)

    key = build(:key, permissions: [build(:key_permission, domain: "docs", resource: "foo")])
    refute Key.verify_permissions?(key, "api", "read")
    refute Key.verify_permissions?(key, "api", "write")
    assert Key.verify_permissions?(key, "docs", "foo")
    refute Key.verify_permissions?(key, "docs", "bar")
    refute Key.verify_permissions?(key, "repositories", nil)

    key = build(:key, permissions: [build(:key_permission, domain: "api")])
    assert Key.verify_permissions?(key, "api", "read")
    assert Key.verify_permissions?(key, "api", "write")
    refute Key.verify_permissions?(key, "repository", "foo")
    refute Key.verify_permissions?(key, "repositories", nil)

    key = build(:key, permissions: [build(:key_permission, domain: "api", resource: "read")])
    assert Key.verify_permissions?(key, "api", "read")
    refute Key.verify_permissions?(key, "api", "write")
    refute Key.verify_permissions?(key, "repository", "foo")
    refute Key.verify_permissions?(key, "repositories", nil)

    key = build(:key, permissions: [build(:key_permission, domain: "api", resource: "write")])
    assert Key.verify_permissions?(key, "api", "read")
    assert Key.verify_permissions?(key, "api", "write")
    refute Key.verify_permissions?(key, "repository", "foo")
    refute Key.verify_permissions?(key, "repositories", nil)
  end
end
