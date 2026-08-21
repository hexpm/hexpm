defmodule Hexpm.Repo.Migrations.AddReleaseSemverSortKey do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION public.hexpm_semver_sort_key(value text)
    RETURNS bytea
    LANGUAGE plpgsql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
    AS $$
    DECLARE
      build_separator integer;
      separator integer;
      precedence text;
      core text;
      prerelease text;
      component text;
      identifier text;
      identifiers text[];
      result bytea := ''::bytea;
    BEGIN
      build_separator := pg_catalog.strpos(value, '+');

      IF build_separator = 0 THEN
        precedence := value;
      ELSE
        precedence := pg_catalog.substr(value, 1, build_separator - 1);
      END IF;

      separator := pg_catalog.strpos(precedence, '-');

      IF separator = 0 THEN
        core := precedence;
        prerelease := NULL;
      ELSE
        core := pg_catalog.substr(precedence, 1, separator - 1);
        prerelease := pg_catalog.substr(precedence, separator + 1);
      END IF;

      FOREACH component IN ARRAY pg_catalog.string_to_array(core, '.') LOOP
        IF component::numeric > 99999999999999 THEN
          RAISE EXCEPTION 'SemVer numeric components must be at most 99999999999999';
        END IF;

        result := result || pg_catalog.int8send(component::bigint);
      END LOOP;

      IF prerelease IS NULL THEN
        RETURN result || pg_catalog.decode('01', 'hex');
      END IF;

      result := result || pg_catalog.decode('00', 'hex');

      IF pg_catalog.octet_length(prerelease) > 64 THEN
        RAISE EXCEPTION 'SemVer prerelease must be at most 64 characters';
      END IF;

      identifiers := pg_catalog.string_to_array(prerelease, '.');

      FOREACH identifier IN ARRAY identifiers LOOP
        IF pg_catalog.translate(identifier, '0123456789', '') = '' THEN
          IF identifier::numeric > 99999999999999 THEN
            RAISE EXCEPTION 'SemVer numeric components must be at most 99999999999999';
          END IF;

          result := result ||
            pg_catalog.decode('01', 'hex') ||
            pg_catalog.int8send(identifier::bigint) ||
            pg_catalog.decode('00', 'hex');
        ELSE
          result := result ||
            pg_catalog.decode('02', 'hex') ||
            identifier::bytea ||
            pg_catalog.decode('00', 'hex');
        END IF;
      END LOOP;

      RETURN result || pg_catalog.decode('00', 'hex');
    END;
    $$
    """)

    execute("SET LOCAL lock_timeout TO '5s'")

    execute("""
    ALTER TABLE public.releases
    ADD COLUMN semver_sort_key bytea
      GENERATED ALWAYS AS (public.hexpm_semver_sort_key(version)) STORED NOT NULL,
    ADD COLUMN semver_stable boolean
      GENERATED ALWAYS AS (
        pg_catalog.strpos(pg_catalog.split_part(version, '+', 1), '-') = 0
      ) STORED NOT NULL
    """)
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    execute("""
    ALTER TABLE public.releases
    DROP COLUMN semver_sort_key,
    DROP COLUMN semver_stable
    """)

    execute("DROP FUNCTION public.hexpm_semver_sort_key(text)")
  end
end
