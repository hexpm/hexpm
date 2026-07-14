defmodule Hexpm.Preview.DataTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Preview.Data

  test "selects the latest stable release and falls back to prereleases" do
    stable_package = insert(:package, name: "stable_preview")
    retirement = %Hexpm.Repository.ReleaseRetirement{reason: "other", message: "retired"}
    insert(:release, package: stable_package, version: "1.0.0", retirement: retirement)
    insert(:release, package: stable_package, version: "2.0.0-rc.1")

    assert Data.latest_version(stable_package.name) == Version.parse!("1.0.0")

    prerelease_package = insert(:package, name: "prerelease_preview")
    insert(:release, package: prerelease_package, version: "1.0.0-rc.1")
    insert(:release, package: prerelease_package, version: "1.0.0-rc.2")

    assert Data.latest_version(prerelease_package.name) == Version.parse!("1.0.0-rc.2")
  end

  test "returns public packages in name order" do
    later = insert(:package, name: "zzz_preview")
    earlier = insert(:package, name: "aaa_preview")

    packages = Data.packages()

    assert Enum.find(packages, &(elem(&1, 0) == earlier.name))
    assert Enum.find(packages, &(elem(&1, 0) == later.name))

    assert Enum.find_index(packages, &(elem(&1, 0) == earlier.name)) <
             Enum.find_index(packages, &(elem(&1, 0) == later.name))
  end
end
