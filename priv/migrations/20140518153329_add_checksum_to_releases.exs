defmodule HexWeb.Repo.Migrations.AddChecksumToReleases do
  use Ecto.Migration

  def up do
    "ALTER TABLE releases
      ADD checksum text"
  end

  def down do
    "ALTER TABLE releases
      DROP IF EXISTS checksum"
  end
end
