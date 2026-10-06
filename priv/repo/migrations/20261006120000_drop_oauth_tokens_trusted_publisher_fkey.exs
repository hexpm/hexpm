defmodule Hexpm.Repo.Migrations.DropOAuthTokensTrustedPublisherFkey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Dropping the foreign key takes ACCESS EXCLUSIVE on `oauth_tokens`, which
    # every token request writes to. Give up rather than queue behind a
    # long-running read and hold every writer behind us.
    execute("SET lock_timeout TO '5s'")

    execute(
      "ALTER TABLE oauth_tokens DROP CONSTRAINT IF EXISTS oauth_tokens_trusted_publisher_id_fkey"
    )

    execute("SET lock_timeout TO DEFAULT")
  end

  def down do
    execute("""
    DELETE FROM oauth_tokens
    WHERE trusted_publisher_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM trusted_publishers WHERE id = oauth_tokens.trusted_publisher_id)
    """)

    execute("SET lock_timeout TO '5s'")

    execute("""
    ALTER TABLE oauth_tokens
      ADD CONSTRAINT oauth_tokens_trusted_publisher_id_fkey
      FOREIGN KEY (trusted_publisher_id) REFERENCES trusted_publishers(id) ON DELETE CASCADE
      NOT VALID
    """)

    execute("SET lock_timeout TO DEFAULT")

    execute("ALTER TABLE oauth_tokens VALIDATE CONSTRAINT oauth_tokens_trusted_publisher_id_fkey")
  end
end
