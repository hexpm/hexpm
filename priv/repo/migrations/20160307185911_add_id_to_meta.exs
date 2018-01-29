defmodule Hexpm.Repo.Migrations.AddIdToMeta do
  use Ecto.Migration

  def up() do
    execute("""
    CREATE OR REPLACE FUNCTION "json_object_set_key"(
      "json"          json,
      "key_to_set"    TEXT,
      "value_to_set"  anyelement
    )
      RETURNS json
      LANGUAGE sql
      IMMUTABLE
      STRICT
    AS $function$
    SELECT concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')::json
      FROM (SELECT *
              FROM json_each("json")
             WHERE "key" <> "key_to_set"
             UNION ALL
            SELECT "key_to_set", to_json("value_to_set")) AS "fields"
    $function$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION "json_object_delete_keys"("json" json, VARIADIC "keys_to_delete" TEXT[])
      RETURNS json
      LANGUAGE sql
      IMMUTABLE
      STRICT
    AS $function$
    SELECT COALESCE(
      (SELECT ('{' || string_agg(to_json("key") || ':' || "value", ',') || '}')
       FROM json_each("json")
       WHERE "key" <> ALL ("keys_to_delete")),
      '{}'
    )::json
    $function$;
    """)

    execute("CREATE EXTENSION \"uuid-ossp\"")

    execute(
      "UPDATE packages SET meta = json_object_set_key(meta::json, 'id', uuid_generate_v4())::jsonb"
    )

    execute(
      "UPDATE releases SET meta = json_object_set_key(meta::json, 'id', uuid_generate_v4())::jsonb"
    )
  end

  def drop() do
    execute("DROP EXTENSION \"uuid-ossp\"")

    execute("UPDATE packages SET meta = json_object_delete_keys(meta::json, 'id')::jsonb")
    execute("UPDATE releases SET meta = json_object_delete_keys(meta::json, 'id')::jsonb")
    execute("DROP FUNCTION json_object_set_key")
    execute("DROP FUNCTION json_object_delete_keys")
  end
end
