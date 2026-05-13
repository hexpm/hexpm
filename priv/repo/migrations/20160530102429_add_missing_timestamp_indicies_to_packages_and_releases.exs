defmodule Hexpm.Repo.Migrations.AddimestampIndiciesToPackagesAndReleases do
  use Ecto.Migration

  def up() do
    execute("CREATE INDEX ON packages (inserted_at)")
    execute("CREATE INDEX ON packages (updated_at)")
    execute("CREATE INDEX ON releases (inserted_at)")
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_inserted_at_idx")
    execute("DROP INDEX IF EXISTS packages_updated_at_idx")
    execute("DROP INDEX IF EXISTS releases_inserted_at_idx")
  end
end
