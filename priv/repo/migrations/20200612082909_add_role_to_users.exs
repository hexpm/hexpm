defmodule Hexpm.RepoBase.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:role, :string, default: "basic")
    end
  end
end
