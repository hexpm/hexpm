defmodule Hexpm.RepoBase.Migrations.RemoveKeysRevokedAt do
  use Ecto.Migration

  def change do
    execute "UPDATE keys SET revoke_at = least(revoke_at, revoked_at)"

    drop_if_exists unique_index(:keys, [:user_id, :name],
                     where: "revoked_at IS NULL",
                     name: "keys_user_id_name_revoked_at_key"
                   )

    drop_if_exists unique_index(:keys, [:organization_id, :name],
                     where: "revoked_at IS NULL",
                     name: "keys_organization_id_name_revoked_at_key"
                   )

    drop_if_exists index(:keys, :name)

    create_if_not_exists index(:keys, [:user_id, :name])
    create_if_not_exists index(:keys, [:organization_id, :name])
    create_if_not_exists index(:keys, [:public])

    alter table(:keys) do
      remove(:revoked_at, :timestamp)
    end
  end
end
