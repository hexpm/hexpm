defmodule Hexpm.RepoBase.Migrations.AddOrganizationSsoPhase2 do
  use Ecto.Migration

  def up do
    create table(:organization_sso_domains) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :domain, :text, null: false
      add :challenge, :text, null: false
      add :challenge_generation, :integer, null: false, default: 1
      add :state, :text, null: false, default: "pending"
      add :verified_at, :utc_datetime_usec
      add :last_checked_at, :utc_datetime_usec
      add :valid_until, :utc_datetime_usec
      add :invalidated_at, :utc_datetime_usec
      add :discovery_enabled, :boolean, null: false, default: false
      add :automatic_linking_enabled, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_sso_domains, [:organization_id, :domain])
    create unique_index(:organization_sso_domains, [:challenge])
    create index(:organization_sso_domains, [:domain])
    create index(:organization_sso_domains, [:state, :last_checked_at])
    create index(:organization_sso_domains, [:valid_until])

    create constraint(:organization_sso_domains, :organization_sso_domain_state,
             check: "state IN ('pending', 'verified', 'invalid')"
           )

    alter table(:organization_sso_transactions) do
      add :candidate_user_id, references(:users, on_delete: :nilify_all)
      add :candidate_email_id, references(:emails, on_delete: :nilify_all)
      add :domain_id, references(:organization_sso_domains, on_delete: :nilify_all)
      add :domain_challenge_generation, :integer
      add :candidate_connection_version, :integer
      add :entrypoint, :text, null: false, default: "organization"
      add :link_method, :text
      add :confirmation_code_hash, :binary
      add :confirmation_expires_at, :utc_datetime_usec
      add :confirmation_verified_at, :utc_datetime_usec
      add :confirmation_attempts, :integer, null: false, default: 0
      add :confirmation_sends, :integer, null: false, default: 0
      add :browser_capability_hash, :binary
    end

    create index(:organization_sso_transactions, [:candidate_user_id])
    create index(:organization_sso_transactions, [:candidate_email_id])
    create index(:organization_sso_transactions, [:domain_id])

    create constraint(:organization_sso_transactions, :organization_sso_transaction_entrypoint,
             check: "entrypoint IN ('organization', 'discovery', 'third_party')"
           )

    create constraint(:organization_sso_transactions, :organization_sso_transaction_link_method,
             check:
               "link_method IS NULL OR link_method IN ('conventional', 'confirmed_primary_email')"
           )

    alter table(:organization_sso_identities) do
      add :link_method, :text, null: false, default: "conventional"
    end

    create constraint(:organization_sso_identities, :organization_sso_identity_link_method,
             check: "link_method IN ('conventional', 'confirmed_primary_email')"
           )
  end

  def down do
    execute """
    LOCK TABLE organization_sso_transactions, email_outbox_entries
    IN ACCESS EXCLUSIVE MODE
    """

    execute """
    DELETE FROM email_outbox_entries
    WHERE category = 'sso.confirmation_code'
    """

    execute """
    DELETE FROM organization_sso_transactions
    WHERE link_method = 'confirmed_primary_email'
    """

    drop constraint(
           :organization_sso_identities,
           :organization_sso_identity_link_method
         )

    alter table(:organization_sso_identities) do
      remove :link_method
    end

    drop constraint(
           :organization_sso_transactions,
           :organization_sso_transaction_entrypoint
         )

    drop constraint(
           :organization_sso_transactions,
           :organization_sso_transaction_link_method
         )

    drop index(:organization_sso_transactions, [:candidate_user_id])
    drop index(:organization_sso_transactions, [:candidate_email_id])
    drop index(:organization_sso_transactions, [:domain_id])

    alter table(:organization_sso_transactions) do
      remove :candidate_user_id
      remove :candidate_email_id
      remove :domain_id
      remove :domain_challenge_generation
      remove :candidate_connection_version
      remove :entrypoint
      remove :link_method
      remove :confirmation_code_hash
      remove :confirmation_expires_at
      remove :confirmation_verified_at
      remove :confirmation_attempts
      remove :confirmation_sends
      remove :browser_capability_hash
    end

    drop table(:organization_sso_domains)
  end
end
