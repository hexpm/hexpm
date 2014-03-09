defmodule HexWeb.Repo.Migrations.AddRegistriesTable do
  use Ecto.Migration

  def up do
    [ "CREATE TYPE building_state AS ENUM ('waiting', 'working', 'done')",

      "CREATE TABLE registries (
        id serial PRIMARY KEY,
        state building_state,
        created timestamp DEFAULT now(),
        started timestamp)",

      "CREATE INDEX ON registries (state)",
      "CREATE INDEX ON registries (started)" ]
  end

  def down do
    [ "DROP TABLE registries",
      "DROP TYPE building_state" ]
  end
end
