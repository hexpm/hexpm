defmodule Hexpm.Repo.Migrations.AddPackagesTables do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE packages (
        id serial PRIMARY KEY,
        name text,
        owner_id integer REFERENCES users,
        meta json,
        created_at timestamp,
        updated_at timestamp)
    """)

    execute("CREATE INDEX ON packages (owner_id)")
    execute("CREATE UNIQUE INDEX ON packages (lower(name) text_pattern_ops)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS packages")
  end
end
