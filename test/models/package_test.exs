defmodule HexWeb.PackageTest do
  use HexWeb.ModelCase

  alias HexWeb.User
  alias HexWeb.Package

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    |> HexWeb.Repo.insert!
    :ok
  end

  test "create package and get" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    user_id = user.id
    assert {:ok, %Package{}} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    assert [%User{id: ^user_id}] = HexWeb.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> HexWeb.Repo.all
    assert is_nil(HexWeb.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:ok, package} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description"}})
    |> HexWeb.Repo.update!
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    assert length(package.meta.maintainers) == 2
  end

  test "validate blank description in metadata" do
    meta = %{
      "maintainers" => ["eric", "josé"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => ""}

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:error, changeset} = Package.create(user, pkg_meta(%{name: "ecto", meta: meta}))
    assert changeset.errors == []
    assert changeset.changes.meta.errors == [description: "can't be blank"]
  end

  test "packages are unique" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:ok, %Package{}} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    assert {:error, _} = Package.create(user, pkg_meta(%{name: "ecto", description: "Domain-specific language"}))
  end

  test "reserved names" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:error, %{errors: [name: "is reserved"]}} = Package.create(user, pkg_meta(%{name: "elixir", description: "Awesomeness."}))
  end
end
