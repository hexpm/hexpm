defmodule Hexpm.Repo.Migrations.AddUserAgentToAuditLogs do
  use Ecto.Migration

  def change() do
    alter table(:audit_logs) do
      add(:user_agent, :string)
    end
  end
end
