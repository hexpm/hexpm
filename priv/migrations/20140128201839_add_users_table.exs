defmodule HexWeb.Repo.Migrations.AddUsersTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE users (
        id serial PRIMARY KEY,
        username text,
        email text UNIQUE,
        password text,
        created timestamp DEFAULT now())",

      "CREATE UNIQUE INDEX ON users (lower(username))" ]
  end

  def down do
    "DROP TABLE IF EXISTS users"
  end
end
