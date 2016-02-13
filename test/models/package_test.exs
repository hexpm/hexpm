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
    assert [%User{id: ^user_id}] = HexWeb.Repo.get_by(Package, name: "ecto") |> Package.owners |> HexWeb.Repo.all
    assert is_nil(HexWeb.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:ok, package} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description"}})
    |> HexWeb.Repo.update!
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    assert length(package.meta["maintainers"]) == 2
  end

  test "validate valid meta" do
    meta = %{
      "maintainers" => ["eric", "josé"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => "so good"}

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:ok, %Package{meta: ^meta}} = Package.create(user, pkg_meta(%{name: "ecto", meta: meta}))
    assert %Package{meta: ^meta} = HexWeb.Repo.get_by(Package, name: "ecto")
  end

  test "ignore unknown meta fields" do
    meta = %{
      "maintainers" => ["eric"],
      "foo"          => "bar",
      "description" => "Lorem ipsum"
    }

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:ok, %Package{}} = Package.create(user, pkg_meta(%{name: "ecto", meta: meta}))
    assert %Package{meta: meta2} = HexWeb.Repo.get_by(Package, name: "ecto")

    assert Map.size(meta2) == 2
  end

  test "validate invalid meta" do
    meta = %{
      "maintainers" => "eric",
      "licenses"     => 123,
      "links"        => ["url"],
      "description"  => ["so bad"]}

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:error, changeset} = Package.create(user, pkg_meta(%{name: "ecto", meta: meta}))
    assert length(changeset.errors) == 1
    assert length(changeset.errors[:meta]) == 4
  end

  test "validate blank description in metadata" do
    meta = %{
      "maintainers" => ["eric", "josé"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => ""}

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert {:error, changeset} = Package.create(user, pkg_meta(%{name: "ecto", meta: meta}))
    assert length(changeset.errors) == 1
    assert length(changeset.errors[:meta]) == 1
    assert changeset.errors[:meta] == [{"description", :missing}]
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
