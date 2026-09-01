defmodule Hexpm.RepoBase.Migrations.DropDetailsFromOrganizationSsoFailures do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_failures) do
      remove(:details, :map, null: false, default: %{})
    end
  end
end
