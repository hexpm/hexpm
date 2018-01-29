defmodule Hexpm.Repo.Migrations.AddRetirementToReleases do
  use Ecto.Migration

  def change() do
    alter table(:releases) do
      add(:retirement, :jsonb)
    end
  end
end
