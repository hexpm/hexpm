defmodule Hexpm.RepoBase.Migrations.AddPackageReportReleaseTable do
  use Ecto.Migration

  def up() do
    create_if_not_exists table(:package_report_releases) do
      add(:package_report_id, references(:package_reports), null: false)
      add(:release_id, references(:releases), null: false)

      timestamps()
    end

    create_if_not_exists(index(:package_report_releases, [:package_report_id]))
    create_if_not_exists(index(:package_report_releases, [:release_id]))
  end

  def drop() do
    drop_if_exists(table("package_report_releases"))
  end
end
