defmodule Hexpm.Repo.Migrations.AddTrustedPublishers do
  use Ecto.Migration

  # oauth_tokens and releases are large and busy, so their constraints are added
  # NOT VALID and validated separately, and their indexes are built concurrently.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists table(:trusted_publishers) do
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :issuer, :string, null: false
      add :repository_owner, :string, null: false
      add :repository_owner_id, :string, null: false
      add :repository_id, :string, null: false
      add :repository, :string, null: false
      add :workflow, :string, null: false
      add :environment, :string, null: false, default: ""

      timestamps()
    end

    create_if_not_exists unique_index(
                           :trusted_publishers,
                           [:package_id, :provider, :repository, :workflow, "lower(environment)"],
                           name: :trusted_publishers_package_config_unique
                         )

    alter table(:oauth_tokens) do
      add_if_not_exists :trusted_publisher_id, :bigint
      add_if_not_exists :oidc_claims, :map
    end

    alter table(:releases) do
      add_if_not_exists :trusted_publisher_id, :bigint
      add_if_not_exists :oidc_claims, :map
    end

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'oauth_tokens_trusted_publisher_id_fkey'
      ) THEN
        ALTER TABLE oauth_tokens
          ADD CONSTRAINT oauth_tokens_trusted_publisher_id_fkey
          FOREIGN KEY (trusted_publisher_id) REFERENCES trusted_publishers(id) ON DELETE CASCADE
          NOT VALID;
      END IF;
    END
    $$
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'releases_trusted_publisher_id_fkey'
      ) THEN
        ALTER TABLE releases
          ADD CONSTRAINT releases_trusted_publisher_id_fkey
          FOREIGN KEY (trusted_publisher_id) REFERENCES trusted_publishers(id) ON DELETE SET NULL
          NOT VALID;
      END IF;
    END
    $$
    """

    drop_if_exists constraint(:oauth_tokens, :user_or_organization_required)

    # A trusted publisher token is minted without an OAuth client, since the
    # OIDC token is the credential; every other grant still needs one.
    execute "ALTER TABLE oauth_tokens ALTER COLUMN client_id DROP NOT NULL"

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'client_required_unless_trusted_publisher'
      ) THEN
        ALTER TABLE oauth_tokens
          ADD CONSTRAINT client_required_unless_trusted_publisher
          CHECK (client_id IS NOT NULL OR grant_type = 'trusted_publisher')
          NOT VALID;
      END IF;
    END
    $$
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'user_or_organization_or_trusted_publisher_required'
      ) THEN
        ALTER TABLE oauth_tokens
          ADD CONSTRAINT user_or_organization_or_trusted_publisher_required
          CHECK (user_id IS NOT NULL OR organization_id IS NOT NULL OR trusted_publisher_id IS NOT NULL)
          NOT VALID;
      END IF;
    END
    $$
    """

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT oauth_tokens_trusted_publisher_id_fkey"

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT user_or_organization_or_trusted_publisher_required"

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT client_required_unless_trusted_publisher"

    execute "ALTER TABLE releases VALIDATE CONSTRAINT releases_trusted_publisher_id_fkey"

    create_if_not_exists index(:oauth_tokens, [:trusted_publisher_id], concurrently: true)

    # OIDC jti must never be reusable, including after token revoke/expiry.
    create_if_not_exists unique_index(
                           :oauth_tokens,
                           [:grant_reference],
                           where:
                             "grant_type = 'trusted_publisher' AND grant_reference IS NOT NULL",
                           name: :oauth_tokens_trusted_publisher_grant_reference_index,
                           concurrently: true
                         )

    create_if_not_exists index(:releases, [:trusted_publisher_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:releases, [:trusted_publisher_id], concurrently: true)

    drop_if_exists index(:oauth_tokens, [:grant_reference],
                     name: :oauth_tokens_trusted_publisher_grant_reference_index,
                     concurrently: true
                   )

    drop_if_exists index(:oauth_tokens, [:trusted_publisher_id], concurrently: true)

    execute "DELETE FROM oauth_tokens WHERE trusted_publisher_id IS NOT NULL"

    drop_if_exists constraint(:oauth_tokens, :client_required_unless_trusted_publisher)

    execute "ALTER TABLE oauth_tokens ALTER COLUMN client_id SET NOT NULL"

    drop_if_exists constraint(:oauth_tokens, :user_or_organization_or_trusted_publisher_required)

    create constraint(:oauth_tokens, :user_or_organization_required,
             check: "user_id IS NOT NULL OR organization_id IS NOT NULL"
           )

    alter table(:releases) do
      remove_if_exists :oidc_claims, :map
      remove_if_exists :trusted_publisher_id, :bigint
    end

    alter table(:oauth_tokens) do
      remove_if_exists :oidc_claims, :map
      remove_if_exists :trusted_publisher_id, :bigint
    end

    drop_if_exists table(:trusted_publishers)
  end
end
