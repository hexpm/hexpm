defmodule HexWeb.Repo.Migrations.AddDocsToReleases do
  use Ecto.Migration

  def up do
    "ALTER TABLE releases
      ADD has_docs boolean DEFAULT false"
  end

  def down do
    "ALTER TABLE releases
      DROP IF EXISTS has_docs"
  end
end
