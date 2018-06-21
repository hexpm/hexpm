defmodule Hexpm.Repo.Migrations.AddUsageInformationToKeys do
  use Ecto.Migration

  def change do
    alter table(:keys) do
      add(:last_use, :jsonb)
    end
  end
end
