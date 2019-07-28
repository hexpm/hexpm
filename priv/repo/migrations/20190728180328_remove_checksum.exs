defmodule Hexpm.RepoBase.Migrations.RemoveChecksum do
  use Ecto.Migration

  def up do
    alter table(:releases) do
      modify(:inner_checksum, :binary, null: false)
      remove(:checksum)
    end
  end

  def down do
    alter table(:releases) do
      modify(:inner_checksum, :binary, null: true)
      add(:checksum, :string)
    end
  end
end
