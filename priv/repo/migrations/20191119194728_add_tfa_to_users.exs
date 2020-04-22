defmodule Hexpm.RepoBase.Migrations.AddTfaToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:tfa, :map)
    end
  end
end
