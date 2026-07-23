defmodule Hexpm.RepoBase.Migrations.AddConfiguredByUserToOrganizationSsoConnections do
  use Ecto.Migration

  def up do
    alter table(:organization_sso_connections) do
      add :configured_by_user_id, references(:users, on_delete: :nilify_all)
    end

    execute("""
    UPDATE organization_sso_connections AS connection
    SET configured_by_user_id = (
      SELECT audit_log.user_id
      FROM audit_logs AS audit_log
      WHERE audit_log.organization_id = connection.organization_id
        AND audit_log.action = 'sso.connection.configure'
        AND audit_log.user_id IS NOT NULL
      ORDER BY audit_log.inserted_at DESC, audit_log.id DESC
      LIMIT 1
    )
    """)
  end

  def down do
    alter table(:organization_sso_connections) do
      remove :configured_by_user_id
    end
  end
end
