defmodule Hexpm.RepoBase.Migrations.AddScimToOrganizationSsoConnections do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_connections) do
      add :scim_token_first, :text
      add :scim_token_second, :text
      add :scim_seat_policy, :text
      add :scim_role, :text, default: "read", null: false
    end

    create index(:organization_sso_connections, [:scim_token_first])
  end
end
