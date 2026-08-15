defmodule Hexpm.Repo.Migrations.CoverDownloadsPackageDayIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS downloads_package_id_day_downloads_idx
    ON downloads (package_id, day) INCLUDE (downloads)
    """)

    execute("DROP INDEX CONCURRENTLY IF EXISTS downloads_package_id_day_idx")

    # Dropping the constraint is a catalog change, but it still needs ACCESS
    # EXCLUSIVE and would otherwise queue behind a long read and block writers.
    execute("SET lock_timeout TO '5s'")
    execute("ALTER TABLE downloads DROP CONSTRAINT IF EXISTS downloads_pkey")
    execute("SET lock_timeout TO DEFAULT")
  end

  def down() do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS downloads_package_id_day_idx
    ON downloads (package_id, day)
    """)

    execute("DROP INDEX CONCURRENTLY IF EXISTS downloads_package_id_day_downloads_idx")

    execute("""
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS downloads_pkey ON downloads (id)
    """)

    execute("ALTER TABLE downloads ADD CONSTRAINT downloads_pkey PRIMARY KEY USING INDEX downloads_pkey")
  end
end
