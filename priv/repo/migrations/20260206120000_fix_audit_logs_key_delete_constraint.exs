defmodule Hexpm.Repo.Migrations.FixAuditLogsKeyDeleteConstraint do
  use Ecto.Migration

  def up() do
    execute("ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_key_id_fkey")

    execute("""
      ALTER TABLE audit_logs
        ADD CONSTRAINT audit_logs_key_id_fkey
          FOREIGN KEY (key_id) REFERENCES keys(id) ON DELETE SET NULL
    """)
  end

  def down() do
    execute("ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_key_id_fkey")

    execute("""
      ALTER TABLE audit_logs
        ADD CONSTRAINT audit_logs_key_id_fkey
          FOREIGN KEY (key_id) REFERENCES keys(id) ON DELETE RESTRICT
    """)
  end
end
