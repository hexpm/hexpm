defmodule Hexpm.Repo.Migrations.AddKeysTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE keys (
        id serial PRIMARY KEY,
        user_id integer REFERENCES users,
        name text,
        secret text UNIQUE,
        created_at timestamp,
        updated_at timestamp,
        UNIQUE (user_id, name))
    """)
  end

  def down() do
    execute("DROP TABLE keys")
  end
end
