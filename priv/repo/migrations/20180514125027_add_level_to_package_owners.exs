defmodule Hexpm.Repo.Migrations.AddLevelToPackageOwners do
  use Ecto.Migration

  def change do
    alter table(:package_owners) do
      add(:level, :string, default: "full", null: false)
    end

    execute("ALTER TABLE package_owners RENAME owner_id TO user_id")
  end
end
