defmodule Hexpm.Repository.PackageTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.User
  alias Hexpm.Repository.Package

  setup do
    user = insert(:user)
    organization = insert(:organization)
    %{user: user, organization: organization}
  end

  test "create package and get", %{user: user, organization: organization} do
    user_id = user.id

    Package.build(organization, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!()

    assert [%User{id: ^user_id}] =
             Hexpm.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> Hexpm.Repo.all()

    assert is_nil(Hexpm.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user, organization: organization} do
    package =
      Package.build(organization, user, pkg_meta(%{name: "ecto", description: "original"}))
      |> Hexpm.Repo.insert!()

    Package.update(package, %{
      "meta" => %{
        "description" => "updated",
        "licenses" => ["Apache"]
      }
    })
    |> Hexpm.Repo.update!()

    package = Hexpm.Repo.get_by(Package, name: "ecto")
    assert package.meta.description == "updated"
  end

  test "validate blank description in metadata", %{user: user, organization: organization} do
    changeset = Package.build(organization, user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert changeset.changes.meta.errors == []

    organization = %{organization | id: 1}
    changeset = Package.build(organization, user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert [description: {"can't be blank", _}] = changeset.changes.meta.errors
  end

  test "validate invalid link in metadata", %{user: user, organization: organization} do
    meta =
      pkg_meta(%{
        name: "ecto",
        description: "DSL",
        links: %{"docs" => "https://hexdocs.pm", "a" => "aaa", "b" => "bbb"}
      })

    changeset = Package.build(organization, user, meta)

    assert changeset.errors == []

    assert [links: {"invalid link \"aaa\"", _}, links: {"invalid link \"bbb\"", _}] =
             changeset.changes.meta.errors
  end

  test "packages are unique", %{user: user, organization: organization} do
    Package.build(organization, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!()

    assert {:error, _} =
             Package.build(
               organization,
               user,
               pkg_meta(%{name: "ecto", description: "Domain-specific language"})
             )
             |> Hexpm.Repo.insert()
  end

  test "reserved names", %{user: user, organization: organization} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} =
             Package.build(
               organization,
               user,
               pkg_meta(%{name: "elixir", description: "Awesomeness."})
             )
             |> Hexpm.Repo.insert()
  end

  test "search organization", %{organization: organization} do
    other_organization = insert(:organization)
    package1 = insert(:package, organization_id: organization.id)
    package2 = insert(:package)

    assert [package1.name] ==
             Package.all([organization], 1, 10, "#{organization.name}/#{package1.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [package2.name] !=
             Package.all([organization], 1, 10, "#{organization.name}/#{package2.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [] ==
             Package.all(
               [other_organization],
               1,
               10,
               "#{organization.name}/#{package1.name}",
               nil,
               nil
             )
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert [] ==
             Package.all([other_organization], 1, 10, "#{package1.name}", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)
  end

  test "search extra metadata", %{user: user, organization: organization} do
    meta = %{
      "licenses" => ["apache", "BSD"],
      "links" => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
      "description" => "description",
      "extra" => %{"foo" => %{"bar" => "baz"}, "list" => ["a", 1]}
    }

    meta2 = Map.put(meta, "extra", %{"foo" => %{"bar" => "baz"}, "list" => ["b", 2]})

    Package.build(organization, user, pkg_meta(%{name: "nerves", description: "DSL"}))
    |> Hexpm.Repo.insert!()
    |> Package.update(%{"meta" => meta})
    |> Hexpm.Repo.update!()

    Package.build(organization, user, pkg_meta(%{name: "nerves_pkg", description: "DSL"}))
    |> Hexpm.Repo.insert!()
    |> Package.update(%{"meta" => meta2})
    |> Hexpm.Repo.update!()

    search = [
      {"name:nerves extra:list,[a]", 1},
      {"name:nerves* extra:foo,bar,baz", 2},
      {"name:nerves* extra:list,[1]", 1}
    ]

    for {s, len} <- search do
      p = Package.all([organization], 1, 10, s, nil, nil) |> Hexpm.Repo.all()
      assert length(p) == len
    end
  end

  test "search dependants", %{organization: organization} do
    insert(:package, name: "nerves", organization_id: organization.id)
    poison = insert(:package, name: "poison", organization_id: organization.id)
    ecto = insert(:package, name: "ecto", organization_id: organization.id)
    phoenix = insert(:package, name: "phoenix", organization_id: organization.id)

    rel = insert(:release, package: ecto)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    rel = insert(:release, package: phoenix)
    insert(:requirement, release: rel, dependency: poison, requirement: "~> 1.0")
    insert(:requirement, release: rel, dependency: ecto, requirement: "~> 1.0")

    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)

    assert ["ecto", "phoenix"] =
             Package.all([organization], 1, 10, "depends:poison", :name, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)

    assert ["phoenix"] =
             Package.all([organization], 1, 10, "depends:poison depends:ecto", nil, nil)
             |> Repo.all()
             |> Enum.map(& &1.name)
  end

  test "sort packages by total downloads", %{organization: organization} do
    %{id: ecto_id} = insert(:package, organization_id: organization.id)
    %{id: phoenix_id} = insert(:package, organization_id: organization.id)
    insert(:release, package_id: phoenix_id, daily_downloads: [build(:download, downloads: 10)])
    insert(:release, package_id: ecto_id, daily_downloads: [build(:download, downloads: 5)])

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    assert [phoenix_id, ecto_id] ==
             Package.all([organization], 1, 10, nil, :total_downloads, nil)
             |> Repo.all()
             |> Enum.map(& &1.id)
  end

  test "sort packages by recent downloads", %{organization: organization} do
    %{id: ecto_id} = insert(:package, organization_id: organization.id)
    %{id: phoenix_id} = insert(:package, organization_id: organization.id)
    %{id: decimal_id} = insert(:package, organization_id: organization.id)

    insert(
      :release,
      package_id: phoenix_id,
      daily_downloads: [build(:download, downloads: 10, day: Hexpm.Utils.utc_days_ago(91))]
    )

    insert(
      :release,
      package_id: decimal_id,
      daily_downloads: [build(:download, downloads: 10, day: Hexpm.Utils.utc_days_ago(35))]
    )

    insert(
      :release,
      package_id: ecto_id,
      daily_downloads: [build(:download, downloads: 5, day: Hexpm.Utils.utc_days_ago(10))]
    )

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    assert [decimal_id, ecto_id, phoenix_id] ==
             Package.all([organization], 1, 10, nil, :recent_downloads, nil)
             |> Repo.all()
             |> Enum.map(& &1.id)
  end
end
