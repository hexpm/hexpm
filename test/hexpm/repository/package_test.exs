defmodule Hexpm.Repository.PackageTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.User
  alias Hexpm.Repository.Package

  setup do
    %{user: create_user("eric", "eric@mail.com", "ericeric")}
  end

  test "create package and get", %{user: user} do
    user_id = user.id

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!
    assert [%User{id: ^user_id}] = Hexpm.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> Hexpm.Repo.all
    assert is_nil(Hexpm.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user} do
    package = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description", "licenses" => ["Apache"]}})
    |> Hexpm.Repo.update!
    package = Hexpm.Repo.get_by(Package, name: "ecto")
    assert length(package.meta.maintainers) == 2
  end

  test "validate blank description in metadata", %{user: user} do
    changeset = Package.build(user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert [description: {"can't be blank", _}] = changeset.changes.meta.errors
  end

  test "validate invalid link in metadata", %{user: user} do
    meta = pkg_meta(%{name: "ecto", description: "DSL",
                      links: %{"docs" => "https://hexdocs.pm", "a" => "aaa", "b" => "bbb"}})
    changeset = Package.build(user, meta)

    assert changeset.errors == []
    assert [links: {"invalid link \"aaa\"", _},
            links: {"invalid link \"bbb\"", _}] =
           changeset.changes.meta.errors
  end

  test "packages are unique", %{user: user} do
    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> Hexpm.Repo.insert!
    assert {:error, _} = Package.build(user, pkg_meta(%{name: "ecto", description: "Domain-specific language"})) |> Hexpm.Repo.insert
  end

  test "reserved names", %{user: user} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} = Package.build(user, pkg_meta(%{name: "elixir", description: "Awesomeness."})) |> Hexpm.Repo.insert
  end

  test "search extra metadata" do
    meta = %{
      "maintainers"  => ["justin"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
      "description"  => "description",
      "extra"        => %{"foo" => %{"bar" => "baz"}, "list" => ["a", 1]}}

    meta2 = Map.put(meta, "extra", %{"foo" => %{"bar" => "baz"}, "list" => ["b", 2]})

    user = Hexpm.Repo.get_by!(User, username: "eric")

    Package.build(user, pkg_meta(%{name: "nerves", description: "DSL"}))
    |> Hexpm.Repo.insert!
    |> Package.update(%{"meta" => meta})
    |> Hexpm.Repo.update!

    Package.build(user, pkg_meta(%{name: "nerves_pkg", description: "DSL"}))
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

  test "sort packages by downloads", %{user: user} do
    phoenix =
      Package.build(user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
      |> Hexpm.Repo.insert!
    rel =
      Hexpm.Repository.Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
      |> Hexpm.Repo.insert!
    Hexpm.Repo.insert!(%Hexpm.Repository.Download{release: rel, day: Date.utc_today, downloads: 10})

    :ok = Hexpm.Repo.refresh_view(Hexpm.Repository.PackageDownload)

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> Hexpm.Repo.insert!

    packages =
      Package.all(1, 10, nil, :downloads)
      |> Hexpm.Repo.all
      |> Enum.map(& &1.name)

    assert packages == ["phoenix", "ecto"]
  end
end
