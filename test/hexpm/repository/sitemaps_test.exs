defmodule Hexpm.Repository.SitemapsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Sitemaps

  test "public_packages/0 returns sorted public package timestamps" do
    private_repository = insert(:repository)
    insert(:package, repository_id: private_repository.id, name: "private_package")
    later = insert(:package, name: "zzz_preview")
    earlier = insert(:package, name: "aaa_preview")

    packages = Sitemaps.public_packages()

    assert {earlier.name, earlier.updated_at} in packages
    assert {later.name, later.updated_at} in packages
    refute Enum.any?(packages, &(elem(&1, 0) == "private_package"))

    assert Enum.find_index(packages, &(elem(&1, 0) == earlier.name)) <
             Enum.find_index(packages, &(elem(&1, 0) == later.name))
  end
end
