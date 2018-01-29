defmodule Hexpm.Repo.Migrations.AddChecksumToReleases do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE releases
        ADD checksum text
    """)
  end

  def down() do
    execute("""
      ALTER TABLE releases
        DROP IF EXISTS checksum
    """)
  end
end
