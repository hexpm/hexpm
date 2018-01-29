defmodule Hexpm.Repo.Migrations.AddPackageDependantsView do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE MATERIALIZED VIEW package_dependants (
        name,
        dependant_id) AS
          SELECT DISTINCT p3.name AS name, p0.id AS dependant_id
          FROM "packages" AS p0
          INNER JOIN "releases" AS r1 ON r1."package_id" = p0."id"
          INNER JOIN "requirements" AS r2 ON r2."release_id" = r1."id"
          INNER JOIN "packages" AS p3 ON p3."id" = r2."dependency_id"
    """)

    execute("CREATE INDEX ON package_dependants (name)")
  end

  def down() do
    execute("DROP MATERIALIZED VIEW package_dependants")
  end
end
