defmodule Hexpm.Repo.Migrations.AddInstallsTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE IF NOT EXISTS installs (
        id serial PRIMARY KEY,
        hex text,
        elixir text)
    """)
  end

  def down() do
    execute("DROP TABLE IF EXISTS installs")
  end
end
