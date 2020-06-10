defmodule Hexpm.RepoBase.Migrations.AddAffectedReleaseTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE affected_releases (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        package_report_id integer REFERENCES package_reports,

        updated_at timestamp,
        inserted_at timestamp
      )
    """)

    execute("CREATE INDEX ON affected_releases (package_report_id)")

  end

  def drop() do
    execute ("DROP TABLE IF EXISTS affected_releases")
  end
end
