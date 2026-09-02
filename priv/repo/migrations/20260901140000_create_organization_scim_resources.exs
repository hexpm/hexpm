defmodule Hexpm.RepoBase.Migrations.CreateOrganizationScimResources do
  use Ecto.Migration

  def change do
    create table(:organization_scim_resources) do
      add :connection_id, references(:organization_sso_connections, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :scim_id, :uuid, null: false
      add :external_id, :text
      add :user_name, :text, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :invitation_id, references(:organization_invitations, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:organization_scim_resources, [:connection_id, :scim_id])
    create unique_index(:organization_scim_resources, [:connection_id, :user_name])

    create unique_index(:organization_scim_resources, [:connection_id, :user_id],
             where: "user_id IS NOT NULL"
           )

    create index(:organization_scim_resources, [:organization_id])
    create index(:organization_scim_resources, [:user_id])
    create index(:organization_scim_resources, [:invitation_id])
  end
end
