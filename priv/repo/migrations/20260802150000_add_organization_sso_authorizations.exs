defmodule Hexpm.RepoBase.Migrations.AddOrganizationSsoAuthorizations do
  use Ecto.Migration

  def up do
    # The foreign key takes SHARE ROW EXCLUSIVE on `user_sessions`, which the
    # browser request path writes to. Give up rather than queue behind a
    # long-running read and hold every writer behind us.
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:organization_sso_transactions) do
      add :target_user_session_id, references(:user_sessions, on_delete: :delete_all)
    end

    create index(:organization_sso_transactions, [:target_user_session_id])

    drop constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint)

    create constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint,
             check: "entrypoint IN ('organization', 'third_party', 'cli')"
           )

    create table(:organization_sso_authorizations) do
      add :code_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :user_session_id, references(:user_sessions, on_delete: :delete_all), null: false

      add :organization_ids, {:array, :integer}, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_authorizations, [:code_hash])
    create index(:organization_sso_authorizations, [:expires_at])
    create index(:organization_sso_authorizations, [:user_id])
    create index(:organization_sso_authorizations, [:user_session_id])
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    drop table(:organization_sso_authorizations)

    execute("DELETE FROM organization_sso_transactions WHERE entrypoint = 'cli'")

    drop constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint)

    create constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint,
             check: "entrypoint IN ('organization', 'third_party')"
           )

    drop index(:organization_sso_transactions, [:target_user_session_id])

    alter table(:organization_sso_transactions) do
      remove :target_user_session_id
    end
  end
end
