defmodule Hexpm.RepoBase.Migrations.AddPackageReportReleaseTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE package_report_releases (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        package_report_id integer REFERENCES package_reports,

        updated_at timestamp,
        inserted_at timestamp
      )
    """)

    execute("CREATE INDEX ON package_report_releases (package_report_id)")
  end

  def drop() do
    execute("DROP TABLE IF EXISTS package_report_releases")
  end
end
