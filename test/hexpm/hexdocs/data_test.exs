defmodule Hexpm.Hexdocs.DataTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Hexdocs.Data
  alias Hexpm.Repository.ReleaseRetirement

  test "loads documented versions and retired versions directly from the database" do
    package = insert(:package, name: "documented")
    insert(:release, package: package, version: "1.0.0", has_docs: true)

    insert(:release,
      package: package,
      version: "2.0.0",
      has_docs: true,
      retirement: %ReleaseRetirement{reason: "other", message: "retired release"}
    )

    insert(:release, package: package, version: "3.0.0", has_docs: false)

    version_2 = Version.parse!("2.0.0")
    version_1 = Version.parse!("1.0.0")
    assert {[^version_2, ^version_1], retired} = Data.versions("hexpm", package.name)

    assert retired == MapSet.new([version_2])
  end

  test "loads sorted public package names and renders the shared docs sitemap" do
    package = insert(:package, name: "z_docs", docs_updated_at: ~U[2026-01-02 03:04:05Z])
    insert(:package, name: "a_package")
    insert(:release, package: package, version: "1.0.0", has_docs: true)

    names = Data.public_package_names()
    assert Enum.sort(names) == names
    assert "a_package" in names
    assert "z_docs" in names
    assert Data.docs_sitemap() =~ "z_docs/sitemap.xml"
  end
end
