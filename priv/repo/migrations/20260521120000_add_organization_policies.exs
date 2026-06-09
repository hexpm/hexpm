defmodule Hexpm.Repo.Migrations.AddOrganizationPolicies do
  use Ecto.Migration

  def change do
    create table(:organization_policies) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      add :visibility, :string, null: false
      add :repositories, {:array, :jsonb}, null: false, default: []

      timestamps()
    end

    create unique_index(:organization_policies, [:organization_id, :name])

    create constraint(:organization_policies, :visibility_must_be_known,
             check: "visibility IN ('public', 'private')"
           )
  end
end
