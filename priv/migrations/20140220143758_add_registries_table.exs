defmodule ExplexWeb.Repo.Migrations.AddRegistriesTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE registries (
        id serial PRIMARY KEY,
        version integer,
        data bytea,
        created timestamp DEFAULT now())",

      "CREATE INDEX ON registries (version)" ]
  end

  def down do
    "DROP TABLE registries"
  end
end
