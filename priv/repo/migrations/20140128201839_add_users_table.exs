defmodule Hexpm.Repo.Migrations.AddUsersTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE users (
        id serial PRIMARY KEY,
        username text,
        email text UNIQUE,
        password text,
        created_at timestamp,
        updated_at timestamp)
    """)

    execute("CREATE UNIQUE INDEX ON users (lower(username))")
  end

  def down() do
    execute("DROP TABLE IF EXISTS users")
  end
end
