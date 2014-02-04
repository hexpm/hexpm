defmodule ExplexWeb.Repo.Migrations.AddRequirementsTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE requirements (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        dependency_id integer REFERENCES packages,
        requirement text)",

      "CREATE INDEX ON requirements (release_id)" ]
  end

  def down do
    "DROP TABLE requirements"
  end
end
