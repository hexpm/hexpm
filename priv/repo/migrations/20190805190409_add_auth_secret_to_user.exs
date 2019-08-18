defmodule Hexpm.RepoBase.Migrations.AddAuthSecretToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:auth_secret, :binary)
    end
  end
end
