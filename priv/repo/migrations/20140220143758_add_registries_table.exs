defmodule Hexpm.Repo.Migrations.AddRegistriesTable do
  use Ecto.Migration

  def up() do
    execute("CREATE TYPE building_state AS ENUM ('waiting', 'working', 'done')")

    execute("""
      CREATE TABLE registries (
        id serial PRIMARY KEY,
        state building_state,
        created_at timestamp DEFAULT now(),
        started_at timestamp)
    """)

    execute("CREATE INDEX ON registries (state)")
    execute("CREATE INDEX ON registries (started_at)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS registries")
    execute("DROP TYPE IF EXISTS building_state")
  end
end
