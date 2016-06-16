defmodule HexWeb.PackageTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.User
  alias HexWeb.Package

  setup do
    user =
      User.build(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
      |> HexWeb.Repo.insert!

    {:ok, user: user}
  end

  test "create package and get", %{user: user} do
    user_id = user.id

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    assert [%User{id: ^user_id}] = HexWeb.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> HexWeb.Repo.all
    assert is_nil(HexWeb.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user} do
    package = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description", "licenses" => ["Apache"]}})
    |> HexWeb.Repo.update!
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    assert length(package.meta.maintainers) == 2
  end

  test "validate blank description in metadata", %{user: user} do
    meta = %{
      "maintainers" => ["eric", "josé"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => ""}

    assert {:error, changeset} = Package.build(user, pkg_meta(%{name: "ecto", meta: meta})) |> HexWeb.Repo.insert
    assert changeset.errors == []
    assert changeset.changes.meta.errors == [description: {"can't be blank", []}]
  end

  test "packages are unique", %{user: user} do
    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    assert {:error, _} = Package.build(user, pkg_meta(%{name: "ecto", description: "Domain-specific language"})) |> HexWeb.Repo.insert
  end

  test "reserved names", %{user: user} do
    assert {:error, %{errors: [name: {"is reserved", []}]}} = Package.build(user, pkg_meta(%{name: "elixir", description: "Awesomeness."})) |> HexWeb.Repo.insert
  end

  test "search extra metadata" do
    meta = %{
      "maintainers"  => ["justin"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => "description",
      "extra"        => %{"foo" => %{"bar" => "baz"}, "list" => ["a", 1]}}

    meta2 = Map.put(meta, "extra", %{"foo" => %{"bar" => "baz"}, "list" => ["b", 2]})

    user = HexWeb.Repo.get_by!(User, username: "eric")

    Package.build(user, pkg_meta(%{name: "nerves", description: "DSL"}))
    |> HexWeb.Repo.insert!
    |> Package.update(%{"meta" => meta})
    |> HexWeb.Repo.update!

    Package.build(user, pkg_meta(%{name: "nerves_pkg", description: "DSL"}))
    |> HexWeb.Repo.insert!
    |> Package.update(%{"meta" => meta2})
    |> HexWeb.Repo.update!

    search = [
      {"name:nerves extra:list,[a]", 1},
      {"name:nerves% extra:foo,bar,baz", 2},
      {"name:nerves% extra:list,[1]", 1}]
    for {s, len} <- search do
      p = Package.all(1, 10, s, nil)
      |> HexWeb.Repo.all
      assert length(p) == len
    end
  end
end
