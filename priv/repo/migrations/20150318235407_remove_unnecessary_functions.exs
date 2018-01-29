defmodule Hexpm.Repo.Migrations.RemoveUnnecessaryFunctions do
  use Ecto.Migration

  def up() do
    execute("DROP INDEX IF EXISTS packages_description_text")
    execute("DROP FUNCTION IF EXISTS json_access(json, text)")
    execute("DROP FUNCTION IF EXISTS text_match(tsvector, tsquery)")

    execute("""
      CREATE INDEX packages_description_text ON
        packages USING GIN (to_tsvector('english', (meta->'description')::text))
    """)
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_description_text")

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
end
