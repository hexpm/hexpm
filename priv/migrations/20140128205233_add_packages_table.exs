defmodule ExplexWeb.Repo.Migrations.AddPackagesTables do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE packages (
        id serial PRIMARY KEY,
        name text UNIQUE,
        owner_id integer REFERENCES users,
        meta json,
        created timestamp DEFAULT now())",

      "CREATE INDEX ON packages (owner_id)" ]
  end

  def down do
    "DROP TABLE packages"
  end
end
