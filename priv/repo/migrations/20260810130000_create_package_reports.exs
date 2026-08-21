defmodule Hexpm.Repo.Migrations.CreatePackageReports do
  use Ecto.Migration

  def change do
    create table(:package_reports) do
      add :reason, :text, null: false
      add :summary, :text, null: false
      add :description, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :external_id, :text
      add :external_url, :text
      add :external_sign_in_url, :text
      add :package_id, references(:packages), null: false
      add :reporter_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:package_reports, [:package_id, :inserted_at])
    create index(:package_reports, [:reporter_id])
    create index(:package_reports, [:status, :inserted_at])

    create constraint(:package_reports, :package_report_reason,
             check:
               "reason IN ('vulnerability', 'malware', 'spam', 'copyright_infringement', 'other')"
           )

    create constraint(:package_reports, :package_report_status,
             check: "status IN ('pending', 'submitted', 'failed')"
           )
  end
end
