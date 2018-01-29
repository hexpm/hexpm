defmodule Hexpm.Repo.Migrations.AddMetaExtraIndex do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE INDEX packages_meta_extra_idx ON
        packages USING GIN ((meta->'extra') jsonb_path_ops)
    """)
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_meta_extra_idx")
  end
end
