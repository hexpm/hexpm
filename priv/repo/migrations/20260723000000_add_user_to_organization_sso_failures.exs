defmodule Hexpm.RepoBase.Migrations.AddUserToOrganizationSsoFailures do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_failures) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end
  end
end
