defmodule HexWeb.PackageTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.User
  alias HexWeb.Package

  setup do
    %{user: create_user("eric", "eric@mail.com", "ericeric")}
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
    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    assert {:error, _} = Package.build(user, pkg_meta(%{name: "ecto", description: "Domain-specific language"})) |> HexWeb.Repo.insert
  end

  test "reserved names", %{user: user} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} = Package.build(user, pkg_meta(%{name: "elixir", description: "Awesomeness."})) |> HexWeb.Repo.insert
  end

  test "search extra metadata" do
    meta = %{
      "maintainers"  => ["justin"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
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
      {"name:nerves* extra:foo,bar,baz", 2},
      {"name:nerves* extra:list,[1]", 1}]
    for {s, len} <- search do
      p = Package.all(1, 10, s, nil)
      |> HexWeb.Repo.all
      assert length(p) == len
    end
  end

  test "sort packages by downloads", %{user: user} do
    phoenix =
      Package.build(user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
      |> HexWeb.Repo.insert!
    rel =
      HexWeb.Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
      |> HexWeb.Repo.insert!
    HexWeb.Repo.insert!(%HexWeb.Download{release: rel, day: HexWeb.Utils.utc_today, downloads: 10})

    :ok = HexWeb.Repo.refresh_view(HexWeb.PackageDownload)

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> HexWeb.Repo.insert!

    packages =
      Package.all(1, 10, nil, :downloads)
      |> HexWeb.Repo.all
      |> Enum.map(& &1.name)

    assert packages == ["phoenix", "ecto"]
  end
end
