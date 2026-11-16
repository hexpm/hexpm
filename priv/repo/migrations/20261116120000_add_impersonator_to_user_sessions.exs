defmodule Hexpm.Repo.Migrations.AddImpersonatorToUserSessions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Adding the foreign key takes SHARE ROW EXCLUSIVE on both tables, which
    # conflicts with the ROW EXCLUSIVE an INSERT takes, and both `users` and
    # `user_sessions` are written on the browser request path. Give up rather
    # than queue behind a long-running read and hold every writer behind us.
    execute("SET lock_timeout TO '5s'")

    execute("""
    ALTER TABLE user_sessions
    ADD COLUMN impersonator_id bigint REFERENCES users(id) ON DELETE CASCADE
    """)

    execute("SET lock_timeout TO DEFAULT")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS user_sessions_impersonator_id_index
    ON user_sessions (impersonator_id) WHERE impersonator_id IS NOT NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS user_sessions_impersonator_id_index")

    execute("SET lock_timeout TO '5s'")
    execute("ALTER TABLE user_sessions DROP COLUMN impersonator_id")
    execute("SET lock_timeout TO DEFAULT")
  end
end
