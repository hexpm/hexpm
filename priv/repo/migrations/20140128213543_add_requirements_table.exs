defmodule Hexpm.Repo.Migrations.AddRequirementsTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE requirements (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        dependency_id integer REFERENCES packages,
        requirement text)
    """)

    execute("CREATE INDEX ON requirements (release_id)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS requirements")
  end
end
