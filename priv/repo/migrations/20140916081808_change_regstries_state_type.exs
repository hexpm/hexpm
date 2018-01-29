defmodule Hexpm.Repo.Migrations.ChangeRegstriesStateType do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE registries
        DROP state,
        ADD state text
    """)

    execute("CREATE INDEX ON registries (state)")

    execute("DROP TYPE building_state")
  end

  def down() do
    execute("CREATE TYPE building_state AS ENUM ('waiting', 'working', 'done')")

    execute("""
      ALTER TABLE registries
        DROP state
        ADD state building_state
    """)

    execute("CREATE INDEX ON registries (state)")
  end
end
