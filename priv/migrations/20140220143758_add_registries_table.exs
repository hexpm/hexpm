defmodule HexWeb.Repo.Migrations.AddRegistriesTable do
  use Ecto.Migration

  def up do
    [ "CREATE TYPE building_state AS ENUM ('waiting', 'working', 'done')",

      "CREATE TABLE registries (
        id serial PRIMARY KEY,
        state building_state,
        created_at timestamp DEFAULT now(),
        started_at timestamp)",

      "CREATE INDEX ON registries (state)",
      "CREATE INDEX ON registries (started_at)" ]
  end

  def down do
    [ "DROP TABLE IF EXISTS registries",
      "DROP TYPE IF EXISTS building_state" ]
  end
end
