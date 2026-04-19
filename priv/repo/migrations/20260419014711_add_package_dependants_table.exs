defmodule Hexpm.Repo.Migrations.AddPackageDependantsTable do
  use Ecto.Migration

  def up() do
    create_if_not_exists table(:package_dependants) do
      add :dependency_id, references(:packages, on_delete: :delete_all), null: false
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :dependant_repository_id, references(:repositories, on_delete: :delete_all), null: false
    end

    create_if_not_exists unique_index(:package_dependants, [:dependency_id, :package_id])

    create_if_not_exists index(:package_dependants, [:dependency_id, :dependant_repository_id],
                           include: [:package_id]
                         )

    execute("""
    CREATE OR REPLACE FUNCTION package_dependants_insert() RETURNS trigger AS $$
    BEGIN
      -- ON CONFLICT DO UPDATE (no-op SET) takes a row-level lock on the
      -- existing (dependency_id, package_id) row, which serializes against
      -- a concurrent DELETE trigger's NOT EXISTS check on the same row.
      -- Without this, a publish + revert race on the same (package, dep)
      -- can leave a stale row missing from package_dependants.
      INSERT INTO package_dependants (dependency_id, package_id, dependant_repository_id)
      SELECT NEW.dependency_id, rel.package_id, p.repository_id
      FROM releases rel
      JOIN packages p ON p.id = rel.package_id
      WHERE rel.id = NEW.release_id
      ON CONFLICT (dependency_id, package_id)
        DO UPDATE SET package_id = EXCLUDED.package_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

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

    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_insert ON requirements")

    execute("""
    CREATE TRIGGER package_dependants_after_requirement_insert
    AFTER INSERT ON requirements
    FOR EACH ROW EXECUTE FUNCTION package_dependants_insert();
    """)

    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_delete ON requirements")

    execute("""
    CREATE TRIGGER package_dependants_after_requirement_delete
    AFTER DELETE ON requirements
    REFERENCING OLD TABLE AS old_requirements
    FOR EACH STATEMENT EXECUTE FUNCTION package_dependants_delete();
    """)

    execute("""
    INSERT INTO package_dependants (dependency_id, package_id, dependant_repository_id)
    SELECT DISTINCT req.dependency_id, p.id, p.repository_id
    FROM requirements req
    JOIN releases rel ON rel.id = req.release_id
    JOIN packages p ON p.id = rel.package_id
    ON CONFLICT DO NOTHING
    """)
  end

  def down() do
    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_delete ON requirements")
    execute("DROP TRIGGER IF EXISTS package_dependants_after_requirement_insert ON requirements")
    execute("DROP FUNCTION IF EXISTS package_dependants_delete()")
    execute("DROP FUNCTION IF EXISTS package_dependants_insert()")
    drop_if_exists table(:package_dependants)
  end
end
