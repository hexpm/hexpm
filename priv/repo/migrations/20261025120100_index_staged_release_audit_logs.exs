defmodule Hexpm.Repo.Migrations.IndexStagedReleaseAuditLogs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:audit_logs, ["(params -> 'staged_release' ->> 'id')"],
             name: :audit_logs_staged_release_id_index,
             where: "action IN ('release.approve', 'release.reject', 'release.stage_expire')",
             concurrently: true
           )
  end
end
