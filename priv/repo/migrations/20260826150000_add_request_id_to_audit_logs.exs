defmodule Hexpm.RepoBase.Migrations.AddRequestIdToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :request_id, :string
    end
  end
end
