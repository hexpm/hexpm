defmodule Hexpm.RepoBase.Migrations.AddOauthTokenToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :oauth_token_id, references(:oauth_tokens, on_delete: :nilify_all)
    end

    create index(:audit_logs, [:oauth_token_id])
  end
end
