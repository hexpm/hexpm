defmodule Hexpm.RepoBase.Migrations.AddJitMembershipToOrganizationSsoConnections do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_connections) do
      # NULL means just-in-time membership is off. One nullable column rather
      # than a flag plus a policy makes it impossible to turn on without
      # choosing what happens at the seat limit.
      add :jit_seat_policy, :text
      add :jit_role, :text, null: false, default: "read"
    end

    create constraint(:organization_sso_connections, :organization_sso_jit_seat_policy,
             check: "jit_seat_policy IS NULL OR jit_seat_policy IN ('block', 'expand')"
           )

    create constraint(:organization_sso_connections, :organization_sso_jit_role,
             check: "jit_role IN ('admin', 'write', 'read')"
           )
  end
end
