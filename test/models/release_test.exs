defmodule HexWeb.ReleaseTest do
  use HexWeb.ModelCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    Package.create(user, pkg_meta(%{name: "ecto", description: "Ecto is awesome"})) |> HexWeb.Repo.insert!
    Package.create(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> HexWeb.Repo.insert!
    Package.create(user, pkg_meta(%{name: "decimal", description: "Decimal is awesome, too"})) |> HexWeb.Repo.insert!
    :ok
  end

  test "create release and get" do
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    package_id = package.id

    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Release.create(package, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> HexWeb.Repo.insert!
    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           HexWeb.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

    Release.create(package, rel_meta(%{version: "0.0.2", app: "ecto"}), "") |> HexWeb.Repo.insert!
    assert [%Release{version: %Version{major: 0, minor: 0, patch: 2}},
            %Release{version: %Version{major: 0, minor: 0, patch: 1}}] =
           Release.all(package) |> HexWeb.Repo.all |> Release.sort
  end

  test "create release with deps" do
    ecto     = HexWeb.Repo.get_by(Package, name: "ecto")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")
    decimal  = HexWeb.Repo.get_by(Package, name: "decimal")

    Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    Release.create(decimal, rel_meta(%{version: "0.0.2", app: "decimal"}), "") |> HexWeb.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: "decimal", app: "decimal", requirement: "~> 0.0.1", optional: false}],
                      app: "postgrex", version: "0.0.1"})
    Release.create(postgrex, meta, "") |> HexWeb.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: "decimal", app: "decimal", requirement: "~> 0.0.2", optional: false}, %{name: "postgrex", app: "postgrex", requirement: "== 0.0.1", optional: false}],
                      app: "ecto", version: "0.0.1"})
    Release.create(ecto, meta, "") |> HexWeb.Repo.insert!

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

    Release.create(decimal, rel_meta(%{version: "0.1.0", app: "decimal", requirements: []}), "")
    |> HexWeb.Repo.insert!

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 0.1", optional: false}]
    Release.create(ecto, rel_meta(%{version: "0.1.0", app: "ecto", requirements: reqs}), "")
    |> HexWeb.Repo.insert!

    assert %{version: [{"is invalid", [type: HexWeb.Version]}]} =
           Release.create(ecto, rel_meta(%{version: "0.1", app: "ecto"}), "") |> extract_errors

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> fail", optional: false}]
    assert %{requirements: [%{requirement: [{"invalid requirement: \"~> fail\"", []}]}]} =
           Release.create(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: reqs}), "") |> extract_errors

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 1.0", optional: false}]
    assert %{requirements: [%{requirement: [{"Failed to use \"decimal\" because\n  You specified ~> 1.0 in your mix.exs\n", []}]}]} =
           Release.create(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: reqs}), "") |> extract_errors
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn err -> err end)
  end

  test "release version is unique" do
    ecto = HexWeb.Repo.get_by(Package, name: "ecto")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")

    Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> HexWeb.Repo.insert!
    Release.create(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex"}), "") |> HexWeb.Repo.insert!

    assert {:error, %{errors: [version: {"has already been published", []}]}} =
           Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")
           |> HexWeb.Repo.insert
  end

  test "update release" do
    decimal = HexWeb.Repo.get_by(Package, name: "decimal")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")

    Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 0.0.1", optional: false}]
    release = Release.create(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex", requirements: reqs}), "") |> HexWeb.Repo.insert!

    params = params(%{app: "postgrex", requirements: [%{name: "decimal", app: "decimal", requirement: ">= 0.0.1", optional: false}]})
    Release.update(release, params, "") |> HexWeb.Repo.update!

    decimal_id = decimal.id

    release = HexWeb.Repo.get_by!(assoc(postgrex, :releases), version: "0.0.1")
              |> HexWeb.Repo.preload(:requirements)
    assert [%{dependency_id: ^decimal_id, app: "decimal", requirement: ">= 0.0.1", optional: false}] =
           release.requirements
  end

  test "delete release" do
    decimal = HexWeb.Repo.get_by(Package, name: "decimal")
    postgrex = HexWeb.Repo.get_by(Package, name: "postgrex")

    release = Release.create(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    Release.delete(release) |> HexWeb.Repo.delete!
    refute HexWeb.Repo.get_by(assoc(postgrex, :releases), version: "0.0.1")
  end
end
