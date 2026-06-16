defmodule Hexpm.Repo.Migrations.AddPolicies do
  use Ecto.Migration

  def change do
    create table(:policies) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :visibility, :string, null: false
      add :repositories, {:array, :jsonb}, null: false, default: []

      timestamps()
    end

    create unique_index(:policies, [:organization_id, :name])

    create constraint(:policies, :visibility_must_be_known,
             check: "visibility IN ('public', 'private')"
           )
  end
end
