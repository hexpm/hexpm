defmodule Hexpm.Repo.Migrations.ChangePackageDescriptionIndex do
  use Ecto.Migration

  def up() do
    execute("DROP INDEX IF EXISTS packages_description_text")

    execute("""
      CREATE INDEX packages_description_text ON
        packages USING GIN (to_tsvector('english', regexp_replace((meta->'description')::text, '/', ' ')))
    """)
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_description_text")

    execute("""
      CREATE INDEX packages_description_text ON
        packages USING GIN (to_tsvector('english', (meta->'description')::text))
    """)
  end
end
