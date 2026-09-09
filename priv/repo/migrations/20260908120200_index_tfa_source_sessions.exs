defmodule Hexpm.RepoBase.Migrations.IndexTFASourceSessions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:user_sessions, [:tfa_source_session_id], concurrently: true)
  end
end
