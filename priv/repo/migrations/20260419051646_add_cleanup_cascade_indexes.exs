defmodule Hexpm.Repo.Migrations.AddCleanupCascadeIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    # Required for the nightly purge of plug sessions. The table has 100M+ rows
    # and the cleanup query filters on updated_at; without an index this would
    # seq-scan the entire heap.
    create_if_not_exists(
      index(:sessions, [:updated_at],
        name: :sessions_updated_at_index,
        concurrently: true
      )
    )

    # Replace the partial oauth_tokens(user_session_id) WHERE revoked_at IS NULL
    # index with a non-partial one. The partial cannot be matched by the FK
    # cascade UPDATE that fires on user_sessions DELETE (the cascade has no
    # revoked_at predicate), forcing a seq scan that is prohibitively slow on
    # the bloated heap during bulk cleanup.
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

    # Drop the ad-hoc index created during the initial production cleanup;
    # superseded by oauth_tokens_user_session_id_full_index above.
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
