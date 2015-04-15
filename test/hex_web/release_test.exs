defmodule HexWeb.ReleaseTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, _} = Package.create(user, %{name: "ecto", meta: %{}})
    {:ok, _} = Package.create(user, %{name: "postgrex", meta: %{}})
    {:ok, _} = Package.create(user, %{name: "decimal", meta: %{}})
    :ok
  end

  test "create release and get" do
    package = Package.get("ecto")
    package_id = package.id
    assert {:ok, %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}}} =
           Release.create(package, %{version: "0.0.1", app: "ecto", requirements: %{}}, "")
    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Release.get(package, "0.0.1")

    assert {:ok, _} = Release.create(package, %{version: "0.0.2", app: "ecto", requirements: %{}}, "")
    assert [ %Release{version: %Version{major: 0, minor: 0, patch: 2}},
             %Release{version: %Version{major: 0, minor: 0, patch: 1}} ] =
           Release.all(package)
  end

  test "create release with deps" do
    ecto     = Package.get("ecto")
    postgrex = Package.get("postgrex")
    decimal  = Package.get("decimal")

    assert {:ok, _} = Release.create(decimal, %{version: "0.0.1", app: "decimal", requirements: %{}}, "")
    assert {:ok, _} = Release.create(decimal, %{version: "0.0.2", app: "decimal", requirements: %{}}, "")
    assert {:ok, _} = Release.create(postgrex, %{version: "0.0.1", app: "postgrex", requirements: %{"decimal" => "~> 0.0.1"}}, "")
    assert {:ok, _} = Release.create(ecto, %{version: "0.0.1", app: "ecto", requirements: %{"decimal" => "~> 0.0.2", "postgrex" => "== 0.0.1"}}, "")

    release = Release.get(ecto, "0.0.1")
    reqs = release.requirements
    assert Dict.size(reqs) == 2
    assert {"postgrex", "postgrex", "== 0.0.1", false} in reqs
    assert {"decimal", "decimal", "~> 0.0.2", false} in reqs
  end

  test "validate release" do
    package = Package.get("ecto")

    assert {:ok, _} =
           Release.create(package, %{version: "0.1.0", app: "ecto", requirements: %{"decimal" => nil}}, "")

    assert {:error, [version: "is invalid"]} =
           Release.create(package, %{version: "0.1", app: "ecto", requirements: %{}}, "")

    assert {:error, [requirements: [{"decimal", "invalid requirement: \"fail\""}]]} =
           Release.create(package, %{version: "0.1.1", app: "ecto", requirements: %{"decimal" => "fail"}}, "")
  end

  test "release version is unique" do
    ecto = Package.get("ecto")
    postgrex = Package.get("postgrex")
    assert {:ok, %Release{}} = Release.create(ecto, %{version: "0.0.1", app: "ecto", requirements: %{}}, "")
    assert {:ok, %Release{}} = Release.create(postgrex, %{version: "0.0.1", app: "postgrex", requirements: %{}}, "")
    assert {:error, _} = Release.create(ecto, %{version: "0.0.1", app: "ecto", requirements: %{}}, "")
  end

  test "update release" do
    decimal = Package.get("decimal")
    postgrex = Package.get("postgrex")

    assert {:ok, _} = Release.create(decimal, %{version: "0.0.1", app: "decimal", requirements: %{}}, "")
    assert {:ok, release} = Release.create(postgrex, %{version: "0.0.1", app: "postgrex", requirements: %{"decimal" => "~> 0.0.1"}}, "")

    Release.update(release, %{app: "postgrex", requirements: %{"decimal" => "~> 0.0.2"}}, "")

    release = Release.get(postgrex, "0.0.1")
    assert [{"decimal", "decimal", "~> 0.0.2", false}] = release.requirements
  end

  test "delete release" do
    decimal = Package.get("decimal")
    postgrex = Package.get("postgrex")

    assert {:ok, release} = Release.create(decimal, %{version: "0.0.1", app: "decimal", requirements: %{}}, "")
    Release.delete(release)
    refute Release.get(postgrex, "0.0.1")
  end
end
