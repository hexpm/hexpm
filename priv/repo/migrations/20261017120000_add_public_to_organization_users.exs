defmodule Hexpm.RepoBase.Migrations.AddPublicToOrganizationUsers do
  use Ecto.Migration

  def change do
    alter table(:organization_users) do
      add :public, :boolean, null: false, default: false
    end
  end
end
