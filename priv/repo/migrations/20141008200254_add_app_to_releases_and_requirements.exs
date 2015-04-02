defmodule HexWeb.Repo.Migrations.AddAppToReleasesAndRequirements do
  use Ecto.Migration

  def up do
    [ "ALTER TABLE releases
        ADD app text",
      "ALTER TABLE requirements
        ADD app text" ]
  end

  def down do
    [ "ALTER TABLE releases
        DROP IF EXISTS app",
      "ALTER TABLE requirements
        DROP IF EXISTS app" ]
  end
end
