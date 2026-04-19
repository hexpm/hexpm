defmodule Hexpm.Repo.Migrations.AddCleanupCascadeIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create_if_not_exists(
      index(:sessions, [:updated_at],
        name: :sessions_updated_at_index,
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:oauth_tokens, [:user_session_id],
        name: :oauth_tokens_user_session_id_full_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:oauth_tokens, [:user_session_id],
        name: :oauth_tokens_user_session_id_index,
        concurrently: true
      )
    )

    execute("DROP INDEX CONCURRENTLY IF EXISTS oauth_tokens_user_session_id_full_idx")
  end

  def down() do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS oauth_tokens_user_session_id_index ON oauth_tokens (user_session_id) WHERE revoked_at IS NULL"
    )

    drop_if_exists(
      index(:oauth_tokens, [:user_session_id],
        name: :oauth_tokens_user_session_id_full_index,
        concurrently: true
      )
    )

    drop_if_exists(
      index(:sessions, [:updated_at],
        name: :sessions_updated_at_index,
        concurrently: true
      )
    )
  end
end
