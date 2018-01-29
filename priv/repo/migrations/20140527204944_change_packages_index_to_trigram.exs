defmodule Hexpm.Repo.Migrations.ChangePackagesIndexToTrigram do
  use Ecto.Migration

  def up() do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE INDEX packages_name_trgm ON packages USING GIN (name gin_trgm_ops)")
    execute("DROP INDEX packages_lower_idx")
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_name_trgm")
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("CREATE UNIQUE INDEX ON packages (lower(name) text_pattern_ops)")
  end
end
