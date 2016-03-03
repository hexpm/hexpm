defmodule HexWeb.ReleaseTest do
  use HexWeb.ModelCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user     = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    {:ok, _} = Package.create(user, pkg_meta(%{name: "ecto", description: "Ecto is awesome"}))
    {:ok, _} = Package.create(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"}))
    {:ok, _} = Package.create(user, pkg_meta(%{name: "decimal", description: "Decimal is awesome, too"}))
    :ok
  end

  test "create release and get" do
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    package_id = package.id
    assert {:ok, %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}}} =
           Release.create(package, rel_meta(%{version: "0.0.1", app: "ecto"}), "")
    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           HexWeb.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

    assert {:ok, _} = Release.create(package, rel_meta(%{version: "0.0.2", app: "ecto"}), "")
    assert [%Release{version: %Version{major: 0, minor: 0, patch: 1}},
            %Release{version: %Version{major: 0, minor: 0, patch: 2}}] =
           Release.all(package) |> HexWeb.Repo.all
  end

  test "create release with deps" do
    ecto     = HexWeb.Repo.get_by(Package, name: "ecto")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")
    decimal  = HexWeb.Repo.get_by(Package, name: "decimal")

    assert {:ok, _} = Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    assert {:ok, _} = Release.create(decimal, rel_meta(%{version: "0.0.2", app: "decimal"}), "")
    assert {:ok, _} = Release.create(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex", requirements: %{"decimal" => "~> 0.0.1"}}), "")
    assert {:ok, _} = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto", requirements: %{"decimal" => "~> 0.0.2", "postgrex" => "== 0.0.1"}}), "")

    postgrex_id = postgrex.id
    decimal_id = decimal.id

    release = HexWeb.Repo.get_by!(assoc(ecto, :releases), version: "0.0.1")
              |> HexWeb.Repo.preload(:requirements)
    assert [%{dependency_id: ^decimal_id, app: "decimal", requirement: "~> 0.0.2", optional: false},
            %{dependency_id: ^postgrex_id, app: "postgrex", requirement: "== 0.0.1", optional: false}] =
           release.requirements
  end

  test "validate release" do
    decimal = HexWeb.Repo.get_by!(Package, name: "decimal")
    ecto = HexWeb.Repo.get_by!(Package, name: "ecto")

    assert {:ok, _} =
           Release.create(decimal, rel_meta(%{version: "0.1.0", app: "decimal", requirements: %{}}), "")

    assert {:ok, _} =
           Release.create(ecto, rel_meta(%{version: "0.1.0", app: "ecto", requirements: %{"decimal" => "~> 0.1"}}), "")

    assert {:error, [version: "is invalid"]} =
           Release.create(ecto, rel_meta(%{version: "0.1", app: "ecto"}), "")

    assert {:error, [requirements: [{"decimal", "invalid requirement: \"fail\""}]]} =
           Release.create(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: %{"decimal" => "fail"}}), "")

    assert {:error, [requirements: "Conflict on decimal\n  mix.exs: ~> 1.0\n"]} =
            Release.create(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: %{"decimal" => "~> 1.0"}}), "")
  end

  test "release version is unique" do
    ecto = HexWeb.Repo.get_by(Package, name: "ecto")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")
    assert {:ok, %Release{}} = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")
    assert {:ok, %Release{}} = Release.create(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex"}), "")
    assert {:error, _} = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")
  end

  test "update release" do
    decimal = HexWeb.Repo.get_by(Package, name: "decimal")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")

    assert {:ok, _} = Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    assert {:ok, release} = Release.create(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex", requirements: %{"decimal" => "~> 0.0.1"}}), "")

    params = params(%{app: "postgrex", requirements: %{"decimal" => ">= 0.0.1"}})
    {:ok, _} = Release.update(release, params, "")

    decimal_id = decimal.id

    release = HexWeb.Repo.get_by!(assoc(postgrex, :releases), version: "0.0.1")
              |> HexWeb.Repo.preload(:requirements)
    assert [%{dependency_id: ^decimal_id, app: "decimal", requirement: ">= 0.0.1", optional: false}] =
           release.requirements
  end

  test "delete release" do
    decimal = HexWeb.Repo.get_by(Package, name: "decimal")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")

    assert {:ok, release} = Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    Release.delete(release) |> HexWeb.Repo.delete!
    refute HexWeb.Repo.get_by(assoc(postgrex, :releases), version: "0.0.1")
  end
end
