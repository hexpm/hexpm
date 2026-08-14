defmodule Hexpm.Repository.PackagesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Packages

  test "public_names/0 returns sorted public package names" do
    insert(:package, name: "z_package")
    insert(:package, name: "a_package")

    private_repository = insert(:repository, name: "private")
    insert(:package, name: "private_package", repository_id: private_repository.id)

    names = Packages.public_names()

    assert Enum.sort(names) == names
    assert "a_package" in names
    assert "z_package" in names
    refute "private_package" in names
  end

  test "attach_latest_releases prefers stable releases and falls back to prereleases" do
    stable = insert(:package, name: "latest_stable")
    prerelease = insert(:package, name: "latest_prerelease")
    empty = insert(:package, name: "latest_empty")

    insert(:release, package: stable, version: "20.0.0-rc.10")

    insert(:release,
      package: stable,
      version: "10.0.0",
      retirement: %{reason: "other", message: "retired"}
    )

    insert(:release, package: prerelease, version: "3.0.0-rc.2")
    insert(:release, package: prerelease, version: "3.0.0-rc.10")

    [stable, prerelease, empty] =
      Packages.attach_latest_releases([stable, prerelease, empty])

    assert stable.latest_release.version == "10.0.0"
    assert prerelease.latest_release.version == "3.0.0-rc.10"
    assert empty.latest_release == nil
  end
end
