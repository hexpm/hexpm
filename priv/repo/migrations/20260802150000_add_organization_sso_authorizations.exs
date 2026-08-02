defmodule Hexpm.RepoBase.Migrations.AddOrganizationSsoAuthorizations do
  use Ecto.Migration

  def up do
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
  end

  def down do
    drop table(:organization_sso_authorizations)

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
