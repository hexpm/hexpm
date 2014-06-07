defmodule HexWeb.Repo.Migrations.AddPackagesDescriptionIndex do
  use Ecto.Migration

  def up do
    [ "CREATE FUNCTION json_access(json, integer) RETURNS json
        AS 'SELECT $1 -> $2;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT",

      "CREATE FUNCTION json_access(json, text) RETURNS json
        AS 'SELECT $1 -> $2;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT",

      "CREATE INDEX packages_description_text ON packages USING GIN (to_tsvector('english', (meta -> 'description')::text))" ]
  end

  def down do
    [ "DROP INDEX IF EXISTS packages_description_text",
      "DROP FUNCTION IF EXISTS json_access" ]
  end
end
