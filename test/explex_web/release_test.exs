defmodule ExplexWeb.ReleaseTest do
  use ExplexWebTest.Case

  alias ExplexWeb.User
  alias ExplexWeb.Package
  alias ExplexWeb.Release
  alias ExplexWeb.Requirement

  setup do
    { :ok, user } = User.create("eric", "eric")
    { :ok, _ } = Package.create("ecto", user, [])
    { :ok, _ } = Package.create("postgrex", user, [])
    { :ok, _ } = Package.create("decimal", user, [])
    :ok
  end

  test "create release and get" do
    package = Package.get("ecto")
    package_id = package.id
    assert { :ok, Release.Entity[package_id: ^package_id, version: "0.0.1"] } =
           Release.create(package, "0.0.1", [])
    assert Release.Entity[package_id: ^package_id, version: "0.0.1"] = Release.get(package, "0.0.1")

    assert { :ok, _ } = Release.create(package, "0.0.2", [])
    assert [Release.Entity[version: "0.0.1"], Release.Entity[version: "0.0.2"]] =
           Release.all(package)
  end

  test "create release with deps" do
    ecto = Package.get("ecto")
    postgrex = Package.get("postgrex")
    decimal = Package.get("decimal")

    assert { :ok, _ } = Release.create(decimal, "0.0.1", [])
    assert { :ok, _ } = Release.create(decimal, "0.0.2", [])
    assert { :ok, _ } = Release.create(postgrex, "0.0.1", [{ "decimal", "~> 0.0.1" }])
    assert { :ok, r } = Release.create(ecto, "0.0.1", [{ "decimal", "~> 0.0.2" }, { "postgrex", "== 0.0.1" }])

    postgrex_id = postgrex.id
    decimal_id = decimal.id
    release_id = r.id
    release = Release.get(ecto, "0.0.1")
    assert [ Requirement.Entity[release_id: ^release_id, dependency_id: ^decimal_id, requirement: "~> 0.0.2"],
             Requirement.Entity[release_id: ^release_id, dependency_id: ^postgrex_id, requirement: "== 0.0.1"]]
           = release.requirements.to_list
  end

  test "validate release version" do
    package = Package.get("ecto")
    assert { :error, [version: "invalid version: 0.1"] } = Release.create(package, "0.1", [])
  end
end
