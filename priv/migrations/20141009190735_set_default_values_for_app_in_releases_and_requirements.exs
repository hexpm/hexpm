defmodule HexWeb.Repo.Migrations.SetDefaultValuesForAppInReleasesAndRequirements do
  use Ecto.Migration

  def up do
    [ "UPDATE releases AS r
        SET app = p.name
        FROM packages AS p
        WHERE r.app IS NULL AND p.id = r.package_id",

      "UPDATE requirements AS r
        SET app = p.name
        FROM packages AS p
        WHERE r.app IS NULL AND p.id = r.dependency_id" ]
  end

  def down do
    [ "UPDATE releases
        SET app = NULL",

      "UPDATE requirements
        SET app = NULL" ]
  end
end
