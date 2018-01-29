defmodule Hexpm.Repo.Migrations.ChangeToJsonb do
  use Ecto.Migration

  def up() do
    execute("""
    ALTER TABLE packages
      ALTER COLUMN meta TYPE jsonb USING meta::text::jsonb
    """)
  end

  def down() do
    execute("""
    ALTER TABLE packages
      ALTER COLUMN meta TYPE json USING meta::text::json
    """)
  end
end
