defmodule Hexpm.Repository.PackageTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.User
  alias Hexpm.Repository.Package

  setup do
    user = insert(:user)
    repository = insert(:repository)
    %{user: user, repository: repository}
  end

  test "create package and get", %{user: user, repository: repository} do
    user_id = user.id

    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!
    assert [%User{id: ^user_id}] = Hexpm.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> Hexpm.Repo.all
    assert is_nil(Hexpm.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user, repository: repository} do
    package = Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description", "licenses" => ["Apache"]}})
    |> Hexpm.Repo.update!
    package = Hexpm.Repo.get_by(Package, name: "ecto")
    assert length(package.meta.maintainers) == 2
  end

  test "validate blank description in metadata", %{user: user, repository: repository} do
    changeset = Package.build(repository, user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert [description: {"can't be blank", _}] = changeset.changes.meta.errors
  end

  test "validate invalid link in metadata", %{user: user, repository: repository} do
    meta = pkg_meta(%{name: "ecto", description: "DSL",
                      links: %{"docs" => "https://hexdocs.pm", "a" => "aaa", "b" => "bbb"}})
    changeset = Package.build(repository, user, meta)

    assert changeset.errors == []
    assert [links: {"invalid link \"aaa\"", _},
            links: {"invalid link \"bbb\"", _}] =
           changeset.changes.meta.errors
  end

  test "packages are unique", %{user: user, repository: repository} do
    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!
    assert {:error, _} = Package.build(repository, user, pkg_meta(%{name: "ecto", description: "Domain-specific language"})) |> Hexpm.Repo.insert
  end

  test "reserved names", %{user: user, repository: repository} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} =
           Package.build(repository, user, pkg_meta(%{name: "elixir", description: "Awesomeness."})) |> Hexpm.Repo.insert
  end

  test "search repository", %{repository: repository} do
    other_repository = insert(:repository)
    package1 = insert(:package, repository_id: repository.id)
    package2 = insert(:package)

    assert Package.all([repository], 1, 10, "#{repository.name}/#{package1.name}", nil, nil) |> Repo.pluck(:name) == [package1.name]
    assert Package.all([repository], 1, 10, "#{repository.name}/#{package2.name}", nil, nil) |> Repo.pluck(:name) != [package2.name]
    assert Package.all([other_repository], 1, 10, "#{repository.name}/#{package1.name}", nil, nil) |> Repo.pluck(:name) == []
    assert Package.all([other_repository], 1, 10, "#{package1.name}", nil, nil) |> Repo.pluck(:name) == []
  end

  test "search extra metadata", %{user: user, repository: repository} do
    meta = %{
      "maintainers"  => ["justin"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
      "description"  => "description",
      "extra"        => %{"foo" => %{"bar" => "baz"}, "list" => ["a", 1]}}

    meta2 = Map.put(meta, "extra", %{"foo" => %{"bar" => "baz"}, "list" => ["b", 2]})

    Package.build(repository, user, pkg_meta(%{name: "nerves", description: "DSL"}))
    |> Hexpm.Repo.insert!
    |> Package.update(%{"meta" => meta})
    |> Hexpm.Repo.update!

    Package.build(repository, user, pkg_meta(%{name: "nerves_pkg", description: "DSL"}))
    |> Hexpm.Repo.insert!
    |> Package.update(%{"meta" => meta2})
    |> Hexpm.Repo.update!

    search = [
      {"name:nerves extra:list,[a]", 1},
      {"name:nerves* extra:foo,bar,baz", 2},
      {"name:nerves* extra:list,[1]", 1}]
    for {s, len} <- search do
      p = Package.all([repository], 1, 10, s, nil, nil) |> Hexpm.Repo.all()
      assert length(p) == len
    end
  end

  test "search dependants", %{repository: repository} do
    insert(:package, name: "nerves", repository_id: repository.id)
    poison = insert(:package, name: "poison", repository_id: repository.id)
    ecto = insert(:package, name: "ecto", repository_id: repository.id)
    phoenix = insert(:package, name: "phoenix", repository_id: repository.id)

    rel = insert(:release, package: ecto)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    rel = insert(:release, package: phoenix)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    insert(:requirement, release: rel, dependency: ecto, requirement: "~> 1.0")

    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)

    assert ["ecto", "phoenix"] = Package.all([repository], 1, 10, "depends:poison", :name, nil) |> Repo.pluck(:name)
    assert ["phoenix"] = Package.all([repository], 1, 10, "depends:poison depends:ecto", nil, nil) |> Repo.pluck(:name)
  end

  test "sort packages by downloads", %{repository: repository} do
    %{id: ecto_id} = insert(:package, repository_id: repository.id)
    %{id: phoenix_id} = insert(:package, repository_id: repository.id)
    insert(:release, package_id: phoenix_id, daily_downloads: [build(:download, downloads: 10)])
    insert(:release, package_id: ecto_id, daily_downloads: [build(:download, downloads: 5)])

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    assert [^phoenix_id, ^ecto_id] = Package.all([repository], 1, 10, nil, :downloads, nil) |> Repo.pluck(:id)
  end
end
