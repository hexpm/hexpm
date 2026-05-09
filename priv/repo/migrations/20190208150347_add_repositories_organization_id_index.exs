defmodule Hexpm.RepoBase.Migrations.AddRepositoriesOrganizationIdIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists(unique_index(:repositories, [:organization_id]))
  end
end
