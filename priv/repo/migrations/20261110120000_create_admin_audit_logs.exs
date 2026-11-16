defmodule Hexpm.Repo.Migrations.CreateAdminAuditLogs do
  use Ecto.Migration

  def change do
    create table(:admin_audit_logs) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :user_data, :map
      add :action, :text, null: false
      add :params, :map, null: false, default: %{}
      add :status, :text, null: false
      add :result, :text
      add :user_agent, :text
      add :remote_ip, :text
      add :request_id, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:admin_audit_logs, [:inserted_at])
    create index(:admin_audit_logs, [:user_id])

    create constraint(:admin_audit_logs, :admin_audit_logs_status,
             check: "status IN ('started', 'ok', 'error', 'raised')"
           )
  end
end
