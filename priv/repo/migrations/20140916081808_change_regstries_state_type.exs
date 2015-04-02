defmodule HexWeb.Repo.Migrations.ChangeRegstriesStateType do
  use Ecto.Migration

  def up do
    [ "ALTER TABLE registries
       DROP state,
       ADD state text",

      "CREATE INDEX ON registries (state)",

      "DROP TYPE building_state" ]
  end

  def down do
    [ "CREATE TYPE building_state AS ENUM ('waiting', 'working', 'done')",

      "ALTER TABLE registries
       DROP state
       ADD state building_state",

      "CREATE INDEX ON registries (state)" ]
  end
end
