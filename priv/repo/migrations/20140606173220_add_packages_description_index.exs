defmodule Hexpm.Repo.Migrations.AddPackagesDescriptionIndex do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE FUNCTION json_access(json, text) RETURNS text
        AS 'SELECT ($1 -> $2)::text;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT
    """)

    execute("""
      CREATE FUNCTION text_match(tsvector, tsquery) RETURNS boolean
        AS 'SELECT $1 @@ $2;'
        LANGUAGE SQL
        IMMUTABLE
        RETURNS NULL ON NULL INPUT
    """)

    execute("""
      CREATE INDEX packages_description_text ON
        packages USING GIN (to_tsvector('english', json_access(meta, 'description')))
    """)
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_description_text")
    execute("DROP FUNCTION IF EXISTS json_access(json, text)")
    execute("DROP FUNCTION IF EXISTS text_match(tsvector, tsquery)")
  end
end
