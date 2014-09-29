defmodule HexWeb.Repo.Migrations.BlockedAddresses do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE blocked_addresses (
        id serial PRIMARY KEY,
        ip text,
        comment text)",

      "CREATE INDEX ON blocked_addresses (ip)" ]
  end

  def down do
    "DROP TABLE IF EXISTS blocked_addresses"
  end
end
