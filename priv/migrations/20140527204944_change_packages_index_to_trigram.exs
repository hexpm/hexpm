defmodule HexWeb.Repo.Migrations.ChangePackagesIndexToTrigram do
  use Ecto.Migration

  def up do
    [ "CREATE EXTENSION pg_trgm",
      "CREATE INDEX packages_name_trgm ON packages USING GIN (name gin_trgm_ops)",
      "DROP INDEX packages_lower_idx" ]
  end

  def down do
    [ "DROP INDEX IF EXISTS packages_name_trgm",
      "DROP EXTENSION IF EXISTS pg_trgm",
      "CREATE UNIQUE INDEX ON packages (lower(name) text_pattern_ops)" ]
  end
end
