defmodule Hexpm.RepoBase.Migrations.AddNewChecksums do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add(:inner_checksum, :binary)
      add(:outer_checksum, :binary)
    end
  end
end
