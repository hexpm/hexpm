defmodule Hexpm.Repo.Migrations.ChangeInstallsElixirReqToArray do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE installs
        ADD elixirs text[]
    """)

    execute("""
      UPDATE installs
        SET elixirs = ARRAY[elixir]
    """)

    execute("""
      ALTER TABLE installs
        DROP elixir
    """)
  end

  def down() do
    execute("""
      ALTER TABLE installs
        ADD elixir text
    """)

    execute("""
      UPDATE installs
        SET elixir = elixirs[1]
    """)

    execute("""
      ALTER TABLE installs
        DROP elixirs
    """)
  end
end
