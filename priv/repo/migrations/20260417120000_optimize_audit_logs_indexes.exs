defmodule Hexpm.Repo.Migrations.OptimizeAuditLogsIndexes do
  use Ecto.Migration

  def up() do
    execute("DROP INDEX IF EXISTS audit_logs_actor_id_index")
    execute("DROP INDEX IF EXISTS audit_logs_user_id_index")
    execute("DROP INDEX IF EXISTS audit_logs_organization_id_index")
    execute("DROP INDEX IF EXISTS audit_logs_params_package_id_index")
    execute("DROP INDEX IF EXISTS audit_logs_inserted_at_index")

    create(
      index(
        :audit_logs,
        [:user_id, "inserted_at DESC"],
        name: "audit_logs_user_id_inserted_at_index"
      )
    )

    create(
      index(
        :audit_logs,
        [:organization_id, "inserted_at DESC"],
        name: "audit_logs_organization_id_inserted_at_index"
      )
    )

    create(
      index(
        :audit_logs,
        ["((params -> 'package' ->> 'id')::integer)", "inserted_at DESC"],
        name: "audit_logs_params_package_id_inserted_at_index"
      )
    )

    create(index(:audit_logs, [:key_id]))
  end

  def down() do
    drop(index(:audit_logs, [:key_id]))

    drop(
      index(
        :audit_logs,
        ["((params -> 'package' ->> 'id')::integer)", "inserted_at DESC"],
        name: "audit_logs_params_package_id_inserted_at_index"
      )
    )

    drop(
      index(
        :audit_logs,
        [:organization_id, "inserted_at DESC"],
        name: "audit_logs_organization_id_inserted_at_index"
      )
    )

    drop(
      index(
        :audit_logs,
        [:user_id, "inserted_at DESC"],
        name: "audit_logs_user_id_inserted_at_index"
      )
    )

    create(index(:audit_logs, [:inserted_at]))

    create(
      index(
        :audit_logs,
        ["((params -> 'package' ->> 'id')::integer)"],
        name: "audit_logs_params_package_id_index"
      )
    )

    create(index(:audit_logs, [:organization_id]))
    create(index(:audit_logs, [:user_id]))
  end
end
