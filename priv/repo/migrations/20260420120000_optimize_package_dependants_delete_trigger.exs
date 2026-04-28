defmodule Hexpm.Repo.Migrations.OptimizePackageDependantsDeleteTrigger do
  use Ecto.Migration

  def up() do
    execute("""
    CREATE UNLOGGED TABLE package_dependants_deleted_releases (
      backend_pid bigint NOT NULL,
      xact_id bigint NOT NULL,
      release_id integer NOT NULL,
      package_id integer NOT NULL
    )
    """)

    create unique_index(
             :package_dependants_deleted_releases,
             [:backend_pid, :xact_id, :release_id]
           )

    execute("""
    CREATE OR REPLACE FUNCTION package_dependants_cache_deleted_release() RETURNS trigger AS $$
    BEGIN
      -- requirements are deleted by ON DELETE CASCADE, and once that happens
      -- the requirements trigger can no longer resolve release_id -> package_id
      -- through releases. Cache the mapping before the release row disappears.
      INSERT INTO package_dependants_deleted_releases (
        backend_pid, xact_id, release_id, package_id
      )
      VALUES (pg_backend_pid(), txid_current(), OLD.id, OLD.package_id)
      ON CONFLICT (backend_pid, xact_id, release_id) DO NOTHING;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION package_dependants_cleanup_deleted_releases() RETURNS trigger AS $$
    BEGIN
      DELETE FROM package_dependants_deleted_releases cache
      USING old_releases
      WHERE cache.backend_pid = pg_backend_pid()
        AND cache.xact_id = txid_current()
        AND cache.release_id = old_releases.id;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION package_dependants_delete() RETURNS trigger AS $$
    BEGIN
      WITH affected AS (
        SELECT DISTINCT
          old_req.dependency_id,
          COALESCE(rel.package_id, cache.package_id) AS package_id
        FROM old_requirements old_req
        LEFT JOIN releases rel ON rel.id = old_req.release_id
        LEFT JOIN package_dependants_deleted_releases cache
          ON cache.backend_pid = pg_backend_pid()
         AND cache.xact_id = txid_current()
         AND cache.release_id = old_req.release_id
        WHERE COALESCE(rel.package_id, cache.package_id) IS NOT NULL
      )
      DELETE FROM package_dependants pd
      USING affected
      WHERE pd.dependency_id = affected.dependency_id
        AND pd.package_id = affected.package_id
        AND NOT EXISTS (
          SELECT 1 FROM requirements req
          JOIN releases rel ON rel.id = req.release_id
          WHERE req.dependency_id = affected.dependency_id
            AND rel.package_id = affected.package_id
        );
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("DROP TRIGGER IF EXISTS package_dependants_before_release_delete ON releases")

    execute("""
    CREATE TRIGGER package_dependants_before_release_delete
    BEFORE DELETE ON releases
    FOR EACH ROW EXECUTE FUNCTION package_dependants_cache_deleted_release();
    """)

    execute("DROP TRIGGER IF EXISTS package_dependants_after_release_delete ON releases")

    execute("""
    CREATE TRIGGER package_dependants_after_release_delete
    AFTER DELETE ON releases
    REFERENCING OLD TABLE AS old_releases
    FOR EACH STATEMENT EXECUTE FUNCTION package_dependants_cleanup_deleted_releases();
    """)
  end

  def down() do
    execute("""
    CREATE OR REPLACE FUNCTION package_dependants_delete() RETURNS trigger AS $$
    BEGIN
      DELETE FROM package_dependants pd
      WHERE pd.dependency_id IN (SELECT DISTINCT dependency_id FROM old_requirements)
        AND NOT EXISTS (
          SELECT 1 FROM requirements req
          JOIN releases rel ON rel.id = req.release_id
          WHERE req.dependency_id = pd.dependency_id
            AND rel.package_id = pd.package_id
        );
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("DROP TRIGGER IF EXISTS package_dependants_after_release_delete ON releases")
    execute("DROP TRIGGER IF EXISTS package_dependants_before_release_delete ON releases")
    execute("DROP FUNCTION IF EXISTS package_dependants_cleanup_deleted_releases()")
    execute("DROP FUNCTION IF EXISTS package_dependants_cache_deleted_release()")

    drop_if_exists unique_index(:package_dependants_deleted_releases, [
                     :backend_pid,
                     :xact_id,
                     :release_id
                   ])

    drop_if_exists table(:package_dependants_deleted_releases)
  end
end
