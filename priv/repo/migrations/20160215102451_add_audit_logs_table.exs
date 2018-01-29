defmodule Hexpm.Repo.Migrations.AddAuditLogsTable do
  use Ecto.Migration

  def change() do
    create table(:audit_logs) do
      add(:actor_id, references(:users))
      add(:action, :string, null: false)
      add(:params, :jsonb, null: false)
      add(:inserted_at, :timestamp, null: false)
    end
  end
end
