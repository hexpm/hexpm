defmodule Hexpm.RepoBase.Migrations.AddOrganizationSsoTransactionUserIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create_if_not_exists(
      index(:organization_sso_transactions, [:user_id, :connection_id],
        name: :organization_sso_transactions_user_id_connection_id_index,
        concurrently: true
      )
    )
  end

  def down() do
    drop_if_exists(
      index(:organization_sso_transactions, [:user_id, :connection_id],
        name: :organization_sso_transactions_user_id_connection_id_index,
        concurrently: true
      )
    )
  end
end
