defmodule Hexpm.Repo.Migrations.IndexStagedReleaseAuditLogsByRelease do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @where "action IN ('release.approve', 'release.reject', 'release.stage_expire')"

  def change do
    create index(
             :audit_logs,
             [
               "(params -> 'staged_release' ->> 'name')",
               "(params -> 'staged_release' ->> 'repository_id')",
               "(params -> 'staged_release' ->> 'version')",
               "(params -> 'staged_release' ->> 'kind')",
               :id
             ],
             name: :audit_logs_staged_release_index,
             where: @where,
             concurrently: true
           )

    drop index(:audit_logs, ["(params -> 'staged_release' ->> 'id')"],
           name: :audit_logs_staged_release_id_index,
           where: @where,
           concurrently: true
         )
  end
end
