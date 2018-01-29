defmodule Hexpm.Repo.Migrations.AddAppToReleasesAndRequirements do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE releases
        ADD app text
    """)

    execute("""
      ALTER TABLE requirements
        ADD app text
    """)
  end

  def down() do
    execute("""
      ALTER TABLE releases
        DROP IF EXISTS app
    """)

    execute("""
      ALTER TABLE requirements
        DROP IF EXISTS app
    """)
  end
end
