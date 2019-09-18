defmodule Hexpm.RepoBase.Migrations.AddTwaEnabledToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:tfa_enabled, :boolean, default: false)
    end
  end
end
