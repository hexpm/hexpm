defmodule Hexpm.Repo.Migrations.AddDocsToReleases do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE releases
        ADD has_docs boolean DEFAULT false
    """)
  end

  def down() do
    execute("""
      ALTER TABLE releases
        DROP IF EXISTS has_docs
    """)
  end
end
