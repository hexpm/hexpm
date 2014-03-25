defmodule HexWeb.Repo.Migrations.AddKeysTable do
  use Ecto.Migration

  def up do
    "CREATE TABLE keys (
      id serial PRIMARY KEY,
      user_id integer REFERENCES users,
      name text,
      secret text UNIQUE,
      created_at timestamp,
      updated_at timestamp,
      UNIQUE (user_id, name))"
  end

  def down do
    "DROP TABLE keys"
  end
end
