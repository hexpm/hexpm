defmodule HexWeb.Repo.Migrations.RemoveUnnecessaryFunctions do
  use Ecto.Migration

  def up do
    [ "DROP INDEX IF EXISTS packages_description_text",
      "DROP FUNCTION IF EXISTS json_access(json, text)",
      "DROP FUNCTION IF EXISTS text_match(tsvector, tsquery)",

      "CREATE INDEX packages_description_text ON packages USING GIN (to_tsvector('english', (meta->'description')::text))" ]
  end

  def down do
    [ "DROP INDEX IF EXISTS packages_description_text",

      "CREATE FUNCTION json_access(json, text) RETURNS text
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
end
