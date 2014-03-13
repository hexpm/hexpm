defmodule HexWeb.Repo.Migrations.AddReleasesTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE releases (
        id serial PRIMARY KEY,
        package_id integer REFERENCES packages,
        version text,
        created timestamp DEFAULT now(),
        UNIQUE (package_id, version))",

      "CREATE INDEX ON releases (package_id)" ]
  end

  def down do
    "DROP TABLE IF EXISTS releases"
  end
end
