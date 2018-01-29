defmodule Hexpm.Repo.Migrations.AddOptionalToRequirements do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE requirements
        ADD optional boolean DEFAULT false
    """)
  end

  def down() do
    execute("""
      ALTER TABLE requirements
        DROP IF EXISTS optional
    """)
  end
end
