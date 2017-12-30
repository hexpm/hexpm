defmodule Hexpm.Repo.Migrations.AddActiveToRepositories do
  use Ecto.Migration

  def change do
    alter table(:repositories) do
      add :active, :boolean, default: true, null: false
      add :billing_active, :boolean, default: false, null: false
    end
  end
end
