defmodule Hexpm.RepoBase.Migrations.MigrateInnerChecksum do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE releases SET inner_checksum = decode(checksum, 'hex')
    """)

    alter table(:releases) do
      modify(:checksum, :string, null: true)
      modify(:inner_checksum, :binary, null: false)
    end
  end

  def down do
    alter table(:releases) do
      modify(:checksum, :string, null: false)
      modify(:inner_checksum, :binary, null: true)
    end

    execute("""
    UPDATE releases SET inner_checksum = NULL
    """)
  end
end
