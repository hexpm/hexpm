defmodule Hexpm.Repo.Migrations.DropOrganizationsPublic do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      remove(:public, :boolean, default: false, null: false)
    end
  end
end
