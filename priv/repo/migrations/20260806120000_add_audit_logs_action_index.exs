defmodule Hexpm.Repo.Migrations.AddAuditLogsActionIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create_if_not_exists(
      index(
        :audit_logs,
        [:action, :inserted_at],
        name: :audit_logs_action_inserted_at_index,
        concurrently: true
      )
    )
  end

  def down() do
    drop_if_exists(
      index(
        :audit_logs,
        [:action, :inserted_at],
        name: :audit_logs_action_inserted_at_index,
        concurrently: true
      )
    )
  end
end
