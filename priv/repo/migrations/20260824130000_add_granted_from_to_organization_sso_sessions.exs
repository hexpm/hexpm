defmodule Hexpm.RepoBase.Migrations.AddGrantedFromToOrganizationSsoSessions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # The foreign key takes SHARE ROW EXCLUSIVE on `user_sessions`, which the
    # browser request path writes to. Give up rather than queue behind a
    # long-running read and hold every writer behind us.
    execute("SET lock_timeout TO '5s'")

    execute("""
    ALTER TABLE organization_sso_sessions
    ADD COLUMN granted_from_user_session_id bigint
      REFERENCES user_sessions(id) ON DELETE CASCADE
    """)

    execute("SET lock_timeout TO DEFAULT")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS
    organization_sso_sessions_granted_from_user_session_id_index
    ON organization_sso_sessions (granted_from_user_session_id)
    """)
  end

  def down do
    execute("""
    DROP INDEX CONCURRENTLY IF EXISTS
    organization_sso_sessions_granted_from_user_session_id_index
    """)

    execute("SET lock_timeout TO '5s'")
    execute("ALTER TABLE organization_sso_sessions DROP COLUMN granted_from_user_session_id")
    execute("SET lock_timeout TO DEFAULT")
  end
end
