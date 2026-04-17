defmodule Hexpm.Repo.Migrations.DropPackageDependantsView do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    execute("DROP MATERIALIZED VIEW package_dependants")
    create(index(:requirements, [:dependency_id], concurrently: true))
  end

  def down() do
    drop(index(:requirements, [:dependency_id], concurrently: true))

    execute("""
      CREATE MATERIALIZED VIEW package_dependants (
        name,
        repo,
        dependant_id) AS
          SELECT DISTINCT p3.name AS name, r4.name as repo, p0.id AS dependant_id
          FROM "packages" AS p0
          INNER JOIN "releases" AS r1 ON r1."package_id" = p0."id"
          INNER JOIN "requirements" AS r2 ON r2."release_id" = r1."id"
          INNER JOIN "packages" AS p3 ON p3."id" = r2."dependency_id"
          INNER JOIN "repositories" AS r4 ON r4."id" = p3."repository_id"
    """)

    execute("CREATE INDEX ON package_dependants (name)")
    execute("CREATE INDEX ON package_dependants (name, repo)")
    execute("CREATE UNIQUE INDEX ON package_dependants (name, repo, dependant_id)")
  end
end
