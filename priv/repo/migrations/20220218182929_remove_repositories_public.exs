defmodule Hexpm.RepoBase.Migrations.RemoveRepositoriesPublic do
  use Ecto.Migration

  def change do
    alter table(:repositories) do
      remove(:public, :boolean, default: false, null: false)
    end
  end
end
