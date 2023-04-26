defmodule Hexpm.RepoBase.Migrations.AddKeyIdToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add(:key_id, references(:keys, on_delete: :restrict))
    end
  end
end
