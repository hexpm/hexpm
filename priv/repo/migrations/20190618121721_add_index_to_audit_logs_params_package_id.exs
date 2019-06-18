defmodule Hexpm.RepoBase.Migrations.AddIndexToAuditLogsParamsPackageId do
  use Ecto.Migration

  def change do
    create(
      index(
        :audit_logs,
        ["((params -> 'package' ->> 'id')::integer)"],
        name: "audit_logs_params_package_id_index"
      )
    )
  end
end
