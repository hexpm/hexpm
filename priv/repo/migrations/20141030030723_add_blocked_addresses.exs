defmodule Hexpm.Repo.Migrations.BlockedAddresses do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE blocked_addresses (
        id serial PRIMARY KEY,
        ip text,
        comment text)
    """)

    execute("CREATE INDEX ON blocked_addresses (ip)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS blocked_addresses")
  end
end
