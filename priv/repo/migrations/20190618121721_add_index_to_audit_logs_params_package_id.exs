defmodule Hexpm.RepoBase.Migrations.AddIndexToAuditLogsParamsPackageId do
  use Ecto.Migration

  def change do
    create_if_not_exists(
      index(
        :audit_logs,
        ["((params -> 'package' ->> 'id')::integer)"],
        name: "audit_logs_params_package_id_index"
      )
    )
  end
end
