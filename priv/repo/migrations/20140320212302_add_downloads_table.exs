defmodule Hexpm.Repo.Migrations.AddStatsTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE downloads (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        downloads integer,
        day date)
    """)

    execute("CREATE INDEX ON downloads (release_id)")
    execute("CREATE INDEX ON downloads (day)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS downloads")
  end
end
