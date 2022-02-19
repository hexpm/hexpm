defmodule Hexpm.Repository.PackageTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.User
  alias Hexpm.Repository.{Package, Repository}

  setup do
    user = insert(:user)
    repository = insert(:repository)
    public_repository = Hexpm.Repo.get(Repository, 1)
    %{user: user, repository: repository, public_repository: public_repository}
  end

  test "create public package and get", %{user: user, public_repository: repository} do
    user_id = user.id

    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!()

    assert [%User{id: ^user_id}] =
             Hexpm.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> Hexpm.Repo.all()

    assert is_nil(Hexpm.Repo.get_by(Package, name: "postgrex"))
  end

  test "create private package and get", %{user: user, repository: repository} do
    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!()

    assert Hexpm.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> Hexpm.Repo.all() == []
    assert is_nil(Hexpm.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user, repository: repository} do
    package =
      Package.build(repository, user, pkg_meta(%{name: "ecto", description: "original"}))
      |> Hexpm.Repo.insert!()

    Package.update(package, %{
      "meta" => %{
        "description" => "updated",
        "licenses" => ["Apache-2.0"]
      }
    })
    |> Hexpm.Repo.update!()

    package = Hexpm.Repo.get_by(Package, name: "ecto")
    assert package.meta.description == "updated"
  end

  test "validate blank description for public package", %{
    user: user,
    public_repository: repository
  } do
    repository = %{repository | id: 1}
    changeset = Package.build(repository, user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert [description: {"can't be blank", _}] = changeset.changes.meta.errors
  end

  test "dont validate blank description for private package", %{
    user: user,
    repository: repository
  } do
    changeset = Package.build(repository, user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert changeset.changes.meta.errors == []
  end

  test "validate invalid link in metadata", %{user: user, repository: repository} do
    meta =
      pkg_meta(%{
        name: "ecto",
        description: "DSL",
        links: %{"docs" => "https://hexdocs.pm", "a" => "aaa", "b" => "bbb"}
      })

    changeset = Package.build(repository, user, meta)

    assert changeset.errors == []

    assert [links: {"invalid link \"aaa\"", _}, links: {"invalid link \"bbb\"", _}] =
             changeset.changes.meta.errors
  end

  test "packages are unique", %{user: user, repository: repository} do
    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!()

    assert {:error, _} =
             Package.build(
               repository,
               user,
               pkg_meta(%{name: "ecto", description: "Domain-specific language"})
             )
             |> Hexpm.Repo.insert()
  end

  test "reserved names", %{user: user, repository: repository} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} =
             Package.build(
               repository,
               user,
               pkg_meta(%{name: "elixir", description: "Awesomeness."})
             )
             |> Hexpm.Repo.insert()
  end

  test "search repository", %{repository: repository} do
    other_repository = insert(:repository)
    package1 = insert(:package, repository_id: repository.id)
    package2 = insert(:package)

    assert [package1.name] ==
             Package.all([repository], 1, 10, "#{repository.name}/#{package1.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [package2.name] !=
             Package.all([repository], 1, 10, "#{repository.name}/#{package2.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [] ==
             Package.all(
               [other_repository],
               1,
               10,
               "#{repository.name}/#{package1.name}",
               nil,
               nil
             )
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [] ==
             Package.all([other_repository], 1, 10, "#{package1.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)
  end

  test "search extra metadata", %{user: user, repository: repository} do
    meta = %{
      "licenses" => ["Apache-2.0", "BSD-3-Clause"],
      "links" => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
      "description" => "description",
      "extra" => %{"foo" => %{"bar" => "baz"}, "list" => ["a", 1]}
    }

    meta2 = Map.put(meta, "extra", %{"foo" => %{"bar" => "baz"}, "list" => ["b", 2]})

    Package.build(repository, user, pkg_meta(%{name: "nerves", description: "DSL"}))
    |> Hexpm.Repo.insert!()
    |> Package.update(%{"meta" => meta})
    |> Hexpm.Repo.update!()

    Package.build(repository, user, pkg_meta(%{name: "nerves_pkg", description: "DSL"}))
    |> Hexpm.Repo.insert!()
    |> Package.update(%{"meta" => meta2})
    |> Hexpm.Repo.update!()

    search = [
      {"name:nerves extra:list,[a]", 1},
      {"name:nerves* extra:foo,bar,baz", 2},
      {"name:nerves* extra:list,[1]", 1}
    ]

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

    assert ["ecto", "phoenix"] =
             Package.all([repository], 1, 10, "depends:#{repository.name}:poison", :name, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert ["phoenix"] =
             Package.all(
               [repository],
               1,
               10,
               "depends:#{repository.name}:poison depends:#{repository.name}:ecto",
               nil,
               nil
             )
             |> Repo.all()
             |> Enum.map(& &1.name)
  end

  test "search dependants is scoped to current repo", %{repository: repository} do
    private_repo = insert(:repository)
    insert(:package, name: "nerves", repository_id: repository.id)
    poison = insert(:package, name: "poison", repository_id: repository.id)
    ecto = insert(:package, name: "ecto", repository_id: private_repo.id)
    phoenix = insert(:package, name: "phoenix", repository_id: repository.id)

    rel = insert(:release, package: ecto)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    rel = insert(:release, package: phoenix)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    insert(:requirement, release: rel, dependency: ecto, requirement: "~> 1.0")

    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)

    assert ["phoenix"] =
             Package.all([repository], 1, 10, "depends:#{repository.name}:poison", :name, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)
  end

  test "sort packages by total downloads", %{repository: repository} do
    %{id: ecto_id} = insert(:package, repository_id: repository.id)
    %{id: phoenix_id} = insert(:package, repository_id: repository.id)

    insert(:release,
      package_id: phoenix_id,
      daily_downloads: [build(:download, package_id: phoenix_id, downloads: 10)]
    )

    insert(:release,
      package_id: ecto_id,
      daily_downloads: [build(:download, package_id: ecto_id, downloads: 5)]
    )

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    assert [phoenix_id, ecto_id] ==
             Package.all([repository], 1, 10, nil, :total_downloads, nil)
             |> Repo.all()
             |> Enum.map(& &1.id)
  end

  test "sort packages by recent downloads", %{repository: repository} do
    %{id: ecto_id} = insert(:package, repository_id: repository.id)
    %{id: phoenix_id} = insert(:package, repository_id: repository.id)
    %{id: decimal_id} = insert(:package, repository_id: repository.id)

    insert(
      :release,
      package_id: phoenix_id,
      daily_downloads: [
        build(:download, package_id: phoenix_id, downloads: 10, day: Hexpm.Utils.utc_days_ago(91))
      ]
    )

    insert(
      :release,
      package_id: decimal_id,
      daily_downloads: [
        build(:download, package_id: decimal_id, downloads: 10, day: Hexpm.Utils.utc_days_ago(35))
      ]
    )

    insert(
      :release,
      package_id: ecto_id,
      daily_downloads: [
        build(:download, package_id: ecto_id, downloads: 5, day: Hexpm.Utils.utc_days_ago(10))
      ]
    )

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    assert [decimal_id, ecto_id, phoenix_id] ==
             Package.all([repository], 1, 10, nil, :recent_downloads, nil)
             |> Repo.all()
             |> Enum.map(& &1.id)
  end
end
