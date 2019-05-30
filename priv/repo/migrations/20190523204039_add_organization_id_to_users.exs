defmodule Hexpm.RepoBase.Migrations.AddOrganizationIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:organization_id, references(:organizations))
    end

    create(unique_index(:users, [:organization_id]))
  end
end
