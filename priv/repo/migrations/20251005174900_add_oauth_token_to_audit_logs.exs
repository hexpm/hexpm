defmodule Hexpm.RepoBase.Migrations.AddOauthTokenToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add_if_not_exists :oauth_token_id, references(:oauth_tokens, on_delete: :nilify_all)
    end

    create_if_not_exists index(:audit_logs, [:oauth_token_id])
  end
end
