defmodule Hexpm.Repo.Migrations.AddSessionTokenPartialIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create_if_not_exists(
      index(:oauth_tokens, [:grant_reference, :client_id],
        name: :oauth_tokens_device_code_lookup_idx,
        where:
          "grant_type = 'urn:ietf:params:oauth:grant-type:device_code' AND revoked_at IS NULL",
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:user_sessions, [:organization_id, :expires_at],
        name: :user_sessions_organization_id_expires_at_active_idx,
        where: "revoked_at IS NULL",
        concurrently: true
      )
    )
  end

  def down() do
    drop_if_exists(
      index(:oauth_tokens, [:grant_reference, :client_id],
        name: :oauth_tokens_device_code_lookup_idx,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:user_sessions, [:organization_id, :expires_at],
        name: :user_sessions_organization_id_expires_at_active_idx,
        concurrently: true
      )
    )
  end
end
