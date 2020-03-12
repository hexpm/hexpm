defmodule Hexpm.RepoBase.Migrations.DropTfaEnabledFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove(:tfa_enabled)
    end
  end
end
