defmodule ExplexWeb.Repo.Migrations.AddUsersTable do
  use Ecto.Migration

  def up do
    "CREATE TABLE users (
      id serial PRIMARY KEY,
      username text UNIQUE,
      password text,
      created timestamp DEFAULT now())"
  end

  def down do
    "DROP TABLE users"
  end
end
