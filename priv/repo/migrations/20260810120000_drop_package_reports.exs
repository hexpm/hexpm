defmodule Hexpm.Repo.Migrations.DropPackageReports do
  use Ecto.Migration

  def up() do
    drop table(:package_report_comments)
    drop table(:package_report_releases)
    drop table(:package_reports)
  end

  def down() do
    raise Ecto.MigrationError,
      message: "this migration is irreversible"
  end
end
