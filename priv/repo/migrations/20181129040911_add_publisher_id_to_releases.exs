defmodule Hexpm.RepoBase.Migrations.AddPublisherIdToReleases do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add(:publisher_id, references(:users))
    end
  end
end
