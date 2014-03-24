defmodule HexWeb.Repo.Migrations.AddStatsTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE downloads (
        id serial PRIMARY KEY,
        release_id integer REFERENCES releases,
        downloads integer,
        day date)",

      "CREATE INDEX ON downloads (release_id)",
      "CREATE INDEX ON downloads (day)" ]
  end

  def down do
    "DROP TABLE IF EXISTS downloads"
  end
end
