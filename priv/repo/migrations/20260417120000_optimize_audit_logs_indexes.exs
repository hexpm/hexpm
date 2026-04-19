defmodule Hexpm.Repo.Migrations.OptimizeAuditLogsIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    drop_if_exists(
      index(:audit_logs, [:user_id], name: "audit_logs_actor_id_index", concurrently: true)
    )

    drop_if_exists(
      index(:audit_logs, [:user_id], name: "audit_logs_user_id_index", concurrently: true)
    )

    drop_if_exists(
      index(:audit_logs, [:organization_id],
        name: "audit_logs_organization_id_index",
        concurrently: true
      )
    )

    drop_if_exists(
      index(:audit_logs, ["((params -> 'package' ->> 'id')::integer)"],
        name: "audit_logs_params_package_id_index",
        concurrently: true
      )
    )

    drop_if_exists(
      index(:audit_logs, [:inserted_at],
        name: "audit_logs_inserted_at_index",
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:audit_logs, [:user_id, "inserted_at DESC"],
        name: "audit_logs_user_id_inserted_at_index",
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:audit_logs, [:organization_id, "inserted_at DESC"],
        name: "audit_logs_organization_id_inserted_at_index",
        concurrently: true
      )
    )

    create_if_not_exists(
      index(:audit_logs, ["((params -> 'package' ->> 'id')::integer)", "inserted_at DESC"],
        name: "audit_logs_params_package_id_inserted_at_index",
        concurrently: true
      )
    )

    create_if_not_exists(index(:audit_logs, [:key_id], concurrently: true))
  end

  def down() do
    drop_if_exists(index(:audit_logs, [:key_id], concurrently: true))

    drop_if_exists(
      index(:audit_logs, ["((params -> 'package' ->> 'id')::integer)", "inserted_at DESC"],
        name: "audit_logs_params_package_id_inserted_at_index",
        concurrently: true
      )
    )

    drop_if_exists(
      index(:audit_logs, [:organization_id, "inserted_at DESC"],
        name: "audit_logs_organization_id_inserted_at_index",
        concurrently: true
      )
    )

    drop_if_exists(
      index(:audit_logs, [:user_id, "inserted_at DESC"],
        name: "audit_logs_user_id_inserted_at_index",
        concurrently: true
      )
    )

    create_if_not_exists(index(:audit_logs, [:inserted_at], concurrently: true))

    create_if_not_exists(
      index(:audit_logs, ["((params -> 'package' ->> 'id')::integer)"],
        name: "audit_logs_params_package_id_index",
        concurrently: true
      )
    )

    create_if_not_exists(index(:audit_logs, [:organization_id], concurrently: true))
    create_if_not_exists(index(:audit_logs, [:user_id], concurrently: true))
  end
end
