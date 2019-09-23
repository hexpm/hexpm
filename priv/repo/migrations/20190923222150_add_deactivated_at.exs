defmodule Hexpm.RepoBase.Migrations.AddDeactivatedAt do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:deactivated_at, :utc_datetime)
    end
  end
end
