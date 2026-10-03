defmodule Hexpm.Repo.Migrations.CreateVarselDisclosures do
  use Ecto.Migration

  def change do
    create table(:varsel_disclosures) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:varsel_disclosures, [:user_id])
  end
end
