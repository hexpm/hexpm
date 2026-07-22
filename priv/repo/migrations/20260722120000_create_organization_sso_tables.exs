defmodule Hexpm.RepoBase.Migrations.CreateOrganizationSsoTables do
  use Ecto.Migration

  def change do
    create table(:organization_sso_connections) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :issuer, :text, null: false
      add :client_id, :text, null: false
      add :client_secret, :text, null: false
      add :pending_client_secret, :text
      add :discovery_document, :map, null: false
      add :jwks_document, :map, null: false
      add :discovery_expires_at, :utc_datetime_usec, null: false
      add :jwks_expires_at, :utc_datetime_usec, null: false
      add :metadata_expires_at, :utc_datetime_usec, null: false
      add :version, :integer, null: false, default: 1
      add :pending_client_secret_version, :integer
      add :tested_at, :utc_datetime_usec
      add :pending_client_secret_tested_at, :utc_datetime_usec
      add :enabled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_connections, [:organization_id])

    create unique_index(:organization_sso_connections, [:id, :organization_id],
             name: :organization_sso_connections_id_organization_id_index
           )

    create table(:organization_sso_identities) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :connection_id, references(:organization_sso_connections, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :issuer, :text, null: false
      add :subject, :text, null: false
      add :provider_email, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_identities, [:connection_id, :issuer, :subject],
             name: :organization_sso_identities_external_identity_index
           )

    create unique_index(:organization_sso_identities, [:connection_id, :user_id])
    create index(:organization_sso_identities, [:organization_id, :user_id])

    execute(
      """
      ALTER TABLE organization_sso_identities
      ADD CONSTRAINT organization_sso_identities_connection_organization_fkey
      FOREIGN KEY (connection_id, organization_id)
      REFERENCES organization_sso_connections (id, organization_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE organization_sso_identities
      DROP CONSTRAINT organization_sso_identities_connection_organization_fkey
      """
    )

    create table(:organization_sso_transactions) do
      add :connection_id, references(:organization_sso_connections, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all)
      add :state_hash, :binary, null: false
      add :nonce, :text
      add :code_verifier, :text
      add :kind, :text, null: false
      add :secret_slot, :text, null: false
      add :connection_version, :integer, null: false
      add :secret_version, :integer, null: false
      add :redirect_uri, :text, null: false
      add :return_path, :text
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      add :issuer, :text
      add :subject, :text
      add :provider_email, :text
      add :link_token_hash, :binary
      add :linked_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_transactions, [:state_hash])
    create index(:organization_sso_transactions, [:expires_at])

    create constraint(:organization_sso_transactions, :organization_sso_transaction_kind,
             check: "kind IN ('login', 'test')"
           )

    create constraint(:organization_sso_transactions, :organization_sso_transaction_secret_slot,
             check: "secret_slot IN ('active', 'pending')"
           )

    create table(:organization_sso_notifications) do
      add :connection_id, references(:organization_sso_connections, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :organization_name, :text, null: false
      add :username, :text, null: false
      add :recipients, :map, null: false
      add :provider_email, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:organization_sso_notifications, [:connection_id, :user_id])

    create constraint(:organization_sso_notifications, :organization_sso_notification_kind,
             check: "kind IN ('identity_linked', 'identity_unlinked', 'email_mismatch')"
           )

    create table(:organization_sso_failures) do
      add :connection_id, references(:organization_sso_connections, on_delete: :delete_all),
        null: false

      add :stage, :text, null: false
      add :code, :text, null: false
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:organization_sso_failures, [:connection_id, :inserted_at])
  end
end
