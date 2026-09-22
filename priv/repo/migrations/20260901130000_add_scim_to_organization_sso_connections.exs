defmodule Hexpm.RepoBase.Migrations.AddScimToOrganizationSsoConnections do
  use Ecto.Migration

  def up do
    # The ALTER takes ACCESS EXCLUSIVE on a table every SSO login reads. Give
    # up rather than queue behind a long-running read and hold every reader
    # behind us.
    execute("SET lock_timeout TO '5s'")

    alter table(:organization_sso_connections) do
      add :scim_token_first, :text
      add :scim_token_second, :text
      add :scim_seat_policy, :text
      add :scim_role, :text, default: "read", null: false
      add :scim_token_generated_by_user_id, references(:users, on_delete: :nilify_all)
      add :scim_token_generated_at, :utc_datetime_usec
      add :scim_token_used_at, :utc_datetime_usec
      add :scim_token_used_ip, :text
    end

    create constraint(:organization_sso_connections, :organization_sso_scim_seat_policy,
             check: "scim_seat_policy IS NULL OR scim_seat_policy IN ('block', 'expand')"
           )

    create constraint(:organization_sso_connections, :organization_sso_scim_role,
             check: "scim_role IN ('admin', 'write', 'read')"
           )

    execute("SET lock_timeout TO DEFAULT")

    create index(:organization_sso_connections, [:scim_token_first])
    create index(:organization_sso_connections, [:scim_token_generated_by_user_id])
  end

  def down do
    execute("SET lock_timeout TO '5s'")

    drop constraint(:organization_sso_connections, :organization_sso_scim_seat_policy)
    drop constraint(:organization_sso_connections, :organization_sso_scim_role)

    alter table(:organization_sso_connections) do
      remove :scim_token_first
      remove :scim_token_second
      remove :scim_seat_policy
      remove :scim_role
      remove :scim_token_generated_by_user_id
      remove :scim_token_generated_at
      remove :scim_token_used_at
      remove :scim_token_used_ip
    end

    execute("SET lock_timeout TO DEFAULT")
  end
end
