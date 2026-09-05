defmodule Hexpm.RepoBase.Migrations.AddSsoEnforcementToOrganizationUsers do
  use Ecto.Migration

  def change do
    alter table(:organization_users) do
      # NULL follows the organization's mode. "enforced" enforces the member
      # whatever the mode says, which is what pilot runs on, and "exempt" never
      # enforces them. A boolean would have to mean the opposite thing in pilot
      # and in required mode, inverting every member on the way between.
      add :sso_enforcement, :text
    end

    create constraint(:organization_users, :organization_users_sso_enforcement,
             check: "sso_enforcement IS NULL OR sso_enforcement IN ('enforced', 'exempt')"
           )
  end
end
