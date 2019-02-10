defmodule Hexpm.RepoBase.Migrations.AddRepositoriesOrganizationIdIndex do
  use Ecto.Migration

  def change do
    create(unique_index(:repositories, [:organization_id]))
  end
end
