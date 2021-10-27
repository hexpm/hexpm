defmodule Hexpm.RepoBase.Migrations.UpdateConstraintOnRevokedAt do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE keys DROP CONSTRAINT keys_user_id_name_revoked_at_key")

    execute(
      "CREATE UNIQUE INDEX keys_user_id_name_revoked_at_key ON keys (user_id, name) WHERE (revoked_at IS NULL)"
    )

    execute(
      "CREATE UNIQUE INDEX keys_organization_id_name_revoked_at_key ON keys (organization_id, name) WHERE (revoked_at IS NULL)"
    )
  end

  def down do
    execute("DROP INDEX keys_organization_id_name_revoked_at_key")
    execute("DROP INDEX keys_user_id_name_revoked_at_key")

    execute(
      "ALTER TABLE keys ADD CONSTRAINT keys_user_id_name_revoked_at_key UNIQUE (user_id, name, revoked_at)"
    )
  end
end
