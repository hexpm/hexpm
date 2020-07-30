defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnPackages do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:packages, [:repository_id_name]))

    execute("DROP MATERIALIZED VIEW IF EXISTS package_dependants")

    alter table(:packages) do
      modify(:name, :string)
    end

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

    create(unique_index(:packages, [:repository_id, "(lower(name))"]))

    create(index(:packages, [:repository_id, :name]))
  end

  def down() do
    drop_if_exists(index(:packages, [:repository_id_name]))
    drop_if_exists(index(:packages, [:repository_id__lower_name]))

    execute("DROP MATERIALIZED VIEW IF EXISTS package_dependants")

    alter table(:packages) do
      modify(:name, :citext)
    end

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

    create(unique_index(:packages, [:repository_id, :name]))
  end
end
