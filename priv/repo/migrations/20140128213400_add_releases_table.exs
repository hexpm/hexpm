defmodule Hexpm.Repo.Migrations.AddReleasesTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE releases (
        id serial PRIMARY KEY,
        package_id integer REFERENCES packages,
        version text,
        created_at timestamp,
        updated_at timestamp,
        UNIQUE (package_id, version))
    """)

    execute("CREATE INDEX ON releases (package_id)")
  end

  def down() do
    execute("DROP TABLE IF EXISTS releases")
  end
end
