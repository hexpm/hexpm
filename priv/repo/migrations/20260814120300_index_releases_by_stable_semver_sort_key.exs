defmodule Hexpm.Repo.Migrations.IndexReleasesByStableSemverSortKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    DROP INDEX CONCURRENTLY IF EXISTS public.releases_package_id_stable_semver_sort_key_desc_index
    """)

    execute("""
    CREATE INDEX CONCURRENTLY releases_package_id_stable_semver_sort_key_desc_index
    ON public.releases (package_id, semver_stable DESC, semver_sort_key DESC)
    """)
  end

  def down do
    execute("""
    DROP INDEX CONCURRENTLY IF EXISTS public.releases_package_id_stable_semver_sort_key_desc_index
    """)
  end
end
