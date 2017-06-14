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
      p = Package.all(1, 10, s, nil)
      |> Hexpm.Repo.all
      assert length(p) == len
    end
  end

  test "search dependants", %{user: user, repository: repository} do
    Package.build(repository, user, pkg_meta(%{name: "nerves", description: "Nerves package"}))
    |> Hexpm.Repo.insert!
    phoenix =
      Package.build(repository, user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
      |> Hexpm.Repo.insert!
    ecto =
      Package.build(repository, user, pkg_meta(%{name: "ecto", description: "Database wrapper"}))
      |> Hexpm.Repo.insert!
    rel =
      Hexpm.Repository.Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
      |> Hexpm.Repo.insert!
    Hexpm.Repo.insert!(%Hexpm.Repository.Requirement{app: "phoenix", release: rel, dependency: ecto})
    Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDependant)

    assert ["phoenix"] = Package.all(1, 10, "depends:ecto", nil)
                         |> Hexpm.Repo.all
                         |> Enum.map(& &1.name)
  end

  test "sort packages by downloads", %{user: user, repository: repository} do
    phoenix =
      Package.build(repository, user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
      |> Hexpm.Repo.insert!
    rel =
      Hexpm.Repository.Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
      |> Hexpm.Repo.insert!
    Hexpm.Repo.insert!(%Hexpm.Repository.Download{release: rel, day: Date.utc_today, downloads: 10})

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    Package.build(repository, user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!

    packages =
      Package.all(1, 10, nil, :downloads)
      |> Hexpm.Repo.all
      |> Enum.map(& &1.name)

    assert packages == ["phoenix", "ecto"]
  end
end
