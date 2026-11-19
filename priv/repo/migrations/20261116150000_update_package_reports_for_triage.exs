defmodule Hexpm.Repo.Migrations.UpdatePackageReportsForTriage do
  use Ecto.Migration

  def up do
    alter table(:package_reports) do
      add :triage_status, :text
      modify :summary, :string, size: 200, null: true
      modify :description, :text, null: true
    end

    execute("UPDATE package_reports SET triage_status = 'open' WHERE reason != 'vulnerability'")

    execute(
      "UPDATE package_reports SET summary = NULL, description = NULL WHERE reason = 'vulnerability'"
    )

    create constraint(:package_reports, :package_report_triage_status,
             check:
               "(reason = 'vulnerability' AND triage_status IS NULL) OR " <>
                 "(reason != 'vulnerability' AND " <>
                 "triage_status IN ('open', 'in_progress', 'resolved', 'dismissed'))"
           )

    create constraint(:package_reports, :package_report_details,
             check:
               "(reason = 'vulnerability' AND summary IS NULL AND description IS NULL) OR " <>
                 "(reason != 'vulnerability' AND summary IS NOT NULL AND description IS NOT NULL)"
           )

    create index(:package_reports, [:triage_status, :inserted_at])
  end

  def down do
    raise Ecto.MigrationError,
      message: "this migration is irreversible"
  end
end
