defmodule Hexpm.Repo.Migrations.AddOwnerToStagedReleases do
  use Ecto.Migration

  def change do
    alter table(:staged_releases) do
      add :owner_id, references(:organizations)
    end
  end
end
