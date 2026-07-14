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
end
