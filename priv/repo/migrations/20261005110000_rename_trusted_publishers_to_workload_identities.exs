defmodule Hexpm.Repo.Migrations.RenameTrustedPublishersToWorkloadIdentities do
  use Ecto.Migration

  # oauth_tokens and releases are large and busy, so their constraints are added
  # NOT VALID and validated separately, and their indexes are built concurrently.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "SET lock_timeout TO '5s'"

    execute "ALTER TABLE IF EXISTS trusted_publishers RENAME TO workload_identities"

    execute "ALTER SEQUENCE IF EXISTS trusted_publishers_id_seq RENAME TO workload_identities_id_seq"

    execute """
    ALTER INDEX IF EXISTS trusted_publishers_package_config_unique
      RENAME TO workload_identities_package_config_unique
    """

    rename_constraints("workload_identities", "trusted_publishers_", "workload_identities_")

    # No foreign key: a workload identity's token outlives the workload identity,
    # because its row is what keeps the OIDC token single-use until it expires.
    alter table(:oauth_tokens) do
      add_if_not_exists :workload_identity_id, :bigint
    end

    alter table(:releases) do
      add_if_not_exists :workload_identity_id, :bigint
    end

    execute "ALTER TABLE oauth_tokens DROP CONSTRAINT IF EXISTS oauth_tokens_trusted_publisher_id_fkey"

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'releases_workload_identity_id_fkey'
      ) THEN
        ALTER TABLE releases
          ADD CONSTRAINT releases_workload_identity_id_fkey
          FOREIGN KEY (workload_identity_id) REFERENCES workload_identities(id) ON DELETE SET NULL
          NOT VALID;
      END IF;
    END
    $$
    """

    drop_if_exists constraint(:oauth_tokens, :client_required_unless_trusted_publisher)

    drop_if_exists constraint(
                     :oauth_tokens,
                     :user_or_organization_or_trusted_publisher_required
                   )

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'client_required_unless_workload_identity'
      ) THEN
        ALTER TABLE oauth_tokens
          ADD CONSTRAINT client_required_unless_workload_identity
          CHECK (client_id IS NOT NULL OR grant_type = 'workload_identity')
          NOT VALID;
      END IF;
    END
    $$
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_or_organization_or_workload_identity_required'
      ) THEN
        ALTER TABLE oauth_tokens
          ADD CONSTRAINT user_or_organization_or_workload_identity_required
          CHECK (user_id IS NOT NULL OR organization_id IS NOT NULL OR workload_identity_id IS NOT NULL)
          NOT VALID;
      END IF;
    END
    $$
    """

    execute "SET lock_timeout TO DEFAULT"

    execute """
    UPDATE oauth_tokens
    SET workload_identity_id = trusted_publisher_id, grant_type = 'workload_identity'
    WHERE trusted_publisher_id IS NOT NULL
    """

    execute """
    UPDATE releases
    SET workload_identity_id = trusted_publisher_id
    WHERE trusted_publisher_id IS NOT NULL
    """

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT client_required_unless_workload_identity"

    execute """
    ALTER TABLE oauth_tokens VALIDATE CONSTRAINT user_or_organization_or_workload_identity_required
    """

    execute "ALTER TABLE releases VALIDATE CONSTRAINT releases_workload_identity_id_fkey"

    create_if_not_exists index(:oauth_tokens, [:workload_identity_id], concurrently: true)

    # OIDC jti must never be reusable, including after token revoke/expiry.
    create_if_not_exists unique_index(
                           :oauth_tokens,
                           [:grant_reference],
                           where:
                             "grant_type = 'workload_identity' AND grant_reference IS NOT NULL",
                           name: :oauth_tokens_workload_identity_grant_reference_index,
                           concurrently: true
                         )

    drop_if_exists index(:oauth_tokens, [:grant_reference],
                     name: :oauth_tokens_trusted_publisher_grant_reference_index,
                     concurrently: true
                   )

    create_if_not_exists index(:releases, [:workload_identity_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:releases, [:workload_identity_id], concurrently: true)

    create_if_not_exists unique_index(
                           :oauth_tokens,
                           [:grant_reference],
                           where:
                             "grant_type = 'trusted_publisher' AND grant_reference IS NOT NULL",
                           name: :oauth_tokens_trusted_publisher_grant_reference_index,
                           concurrently: true
                         )

    drop_if_exists index(:oauth_tokens, [:grant_reference],
                     name: :oauth_tokens_workload_identity_grant_reference_index,
                     concurrently: true
                   )

    drop_if_exists index(:oauth_tokens, [:workload_identity_id], concurrently: true)

    execute "SET lock_timeout TO '5s'"

    drop_if_exists constraint(:oauth_tokens, :client_required_unless_workload_identity)

    drop_if_exists constraint(
                     :oauth_tokens,
                     :user_or_organization_or_workload_identity_required
                   )

    execute """
    UPDATE oauth_tokens
    SET trusted_publisher_id = workload_identity_id, grant_type = 'trusted_publisher'
    WHERE workload_identity_id IS NOT NULL
    """

    execute """
    UPDATE releases
    SET trusted_publisher_id = workload_identity_id
    WHERE workload_identity_id IS NOT NULL
    """

    execute """
    DELETE FROM oauth_tokens
    WHERE trusted_publisher_id IS NOT NULL
      AND trusted_publisher_id NOT IN (SELECT id FROM workload_identities)
    """

    execute """
    ALTER TABLE oauth_tokens
      ADD CONSTRAINT client_required_unless_trusted_publisher
      CHECK (client_id IS NOT NULL OR grant_type = 'trusted_publisher')
      NOT VALID
    """

    execute """
    ALTER TABLE oauth_tokens
      ADD CONSTRAINT user_or_organization_or_trusted_publisher_required
      CHECK (user_id IS NOT NULL OR organization_id IS NOT NULL OR trusted_publisher_id IS NOT NULL)
      NOT VALID
    """

    execute """
    ALTER TABLE oauth_tokens
      ADD CONSTRAINT oauth_tokens_trusted_publisher_id_fkey
      FOREIGN KEY (trusted_publisher_id) REFERENCES workload_identities(id) ON DELETE CASCADE
      NOT VALID
    """

    alter table(:releases) do
      remove_if_exists :workload_identity_id, :bigint
    end

    alter table(:oauth_tokens) do
      remove_if_exists :workload_identity_id, :bigint
    end

    rename_constraints("workload_identities", "workload_identities_", "trusted_publishers_")

    execute """
    ALTER INDEX IF EXISTS workload_identities_package_config_unique
      RENAME TO trusted_publishers_package_config_unique
    """

    execute "ALTER SEQUENCE IF EXISTS workload_identities_id_seq RENAME TO trusted_publishers_id_seq"

    execute "ALTER TABLE IF EXISTS workload_identities RENAME TO trusted_publishers"

    execute "SET lock_timeout TO DEFAULT"

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT client_required_unless_trusted_publisher"

    execute """
    ALTER TABLE oauth_tokens VALIDATE CONSTRAINT user_or_organization_or_trusted_publisher_required
    """

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT oauth_tokens_trusted_publisher_id_fkey"
  end

  # Renaming the primary key constraint renames its index too.
  defp rename_constraints(table, from_prefix, to_prefix) do
    execute """
    DO $$
    DECLARE
      c record;
    BEGIN
      FOR c IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = '#{table}'::regclass AND starts_with(conname, '#{from_prefix}')
      LOOP
        EXECUTE format(
          'ALTER TABLE #{table} RENAME CONSTRAINT %I TO %I',
          c.conname,
          '#{to_prefix}' || substr(c.conname, length('#{from_prefix}') + 1)
        );
      END LOOP;
    END
    $$
    """
  end
end
