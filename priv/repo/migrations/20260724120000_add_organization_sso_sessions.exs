defmodule Hexpm.RepoBase.Migrations.AddOrganizationSsoSessions do
  use Ecto.Migration

  def change do
    create table(:organization_sso_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_session_id, references(:user_sessions, on_delete: :delete_all), null: false

      add :identity_id, references(:organization_sso_identities, on_delete: :delete_all),
        null: false

      add :authenticated_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_sessions, [:user_session_id, :organization_id])
    create index(:organization_sso_sessions, [:organization_id, :user_id])
    create index(:organization_sso_sessions, [:identity_id])
    create index(:organization_sso_sessions, [:expires_at])

    alter table(:organization_sso_transactions) do
      add :entrypoint, :text, null: false, default: "organization"
    end

    create constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint,
             check: "entrypoint IN ('organization', 'third_party')"
           )
  end
end
