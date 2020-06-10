defmodule Hexpm.RepoBase.Migrations.AddPackageReportsTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE package_reports (
        id serial PRIMARY KEY,
        description text,
        state text,
        package_id integer REFERENCES packages,
        author_id integer REFERENCES users,
        release_id integer REFERENCES releases,
        updated_at timestamp,
        inserted_at timestamp
      )
    """)

    execute("CREATE INDEX ON package_reports (author_id)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS package_reports")
  end
end
