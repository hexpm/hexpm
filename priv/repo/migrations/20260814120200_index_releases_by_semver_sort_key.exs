defmodule Hexpm.Repo.Migrations.IndexReleasesBySemverSortKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    DROP INDEX CONCURRENTLY IF EXISTS public.releases_package_id_semver_sort_key_desc_index
    """)

    execute("""
    CREATE INDEX CONCURRENTLY releases_package_id_semver_sort_key_desc_index
    ON public.releases (package_id, semver_sort_key DESC)
    """)
  end

  def down do
    execute("""
    DROP INDEX CONCURRENTLY IF EXISTS public.releases_package_id_semver_sort_key_desc_index
    """)
  end
end
