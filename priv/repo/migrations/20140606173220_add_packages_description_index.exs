defmodule HexWeb.Repo.Migrations.AddPackagesDescriptionIndex do
  use Ecto.Migration

  def up do
    [ "CREATE FUNCTION json_access(json, text) RETURNS text
        AS 'SELECT ($1 -> $2)::text;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT",

      "CREATE FUNCTION text_match(tsvector, tsquery) RETURNS boolean
        AS 'SELECT $1 @@ $2;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT",

      "CREATE INDEX packages_description_text ON packages USING GIN (to_tsvector('english', json_access(meta, 'description')))" ]
  end

  def down do
    [ "DROP INDEX IF EXISTS packages_description_text",
      "DROP FUNCTION IF EXISTS json_access(json, text)",
      "DROP FUNCTION IF EXISTS text_match(tsvector, tsquery)" ]
  end
end
