defmodule HexWeb.Repo.Migrations.AddOptionalToRequirements do
  use Ecto.Migration

  def up do
    "ALTER TABLE requirements
      ADD optional boolean"
  end

  def down do
    "ALTER TABLE requirements
      DROP IF EXISTS optional"
  end
end
