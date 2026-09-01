defmodule Hexpm.RepoBase.Migrations.AddUserSessionToAuthorizationCodes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Adding the foreign key takes SHARE ROW EXCLUSIVE on both tables, which
    # conflicts with the ROW EXCLUSIVE an INSERT takes, and `user_sessions` is
    # written on the browser request path. Give up rather than queue behind a
    # long-running read and hold every writer behind us.
    execute("SET lock_timeout TO '5s'")

    execute("""
    ALTER TABLE authorization_codes
    ADD COLUMN user_session_id bigint REFERENCES user_sessions(id) ON DELETE SET NULL
    """)

    execute("SET lock_timeout TO DEFAULT")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS authorization_codes_user_session_id_index
    ON authorization_codes (user_session_id)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS authorization_codes_user_session_id_index")

    execute("SET lock_timeout TO '5s'")
    execute("ALTER TABLE authorization_codes DROP COLUMN user_session_id")
    execute("SET lock_timeout TO DEFAULT")
  end
end
