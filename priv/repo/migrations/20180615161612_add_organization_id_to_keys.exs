defmodule Hexpm.Repo.Migrations.AddOrganizationIdToKeys do
  use Ecto.Migration

  def change do
    alter table(:keys) do
      add(:organization_id, references(:organizations))
    end

    execute("ALTER TABLE keys ALTER user_id DROP NOT NULL")
  end
end
