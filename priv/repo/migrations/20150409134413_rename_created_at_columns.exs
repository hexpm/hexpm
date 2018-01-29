defmodule Hexpm.Repo.Migrations.RenameCreatedAtColumns do
  use Ecto.Migration

  def up() do
    execute("ALTER TABLE packages RENAME created_at TO inserted_at")
    execute("ALTER TABLE registries RENAME created_at TO inserted_at")
    execute("ALTER TABLE releases RENAME created_at TO inserted_at")
    execute("ALTER TABLE keys RENAME created_at TO inserted_at")
    execute("ALTER TABLE users RENAME created_at TO inserted_at")
  end

  def down() do
    execute("ALTER TABLE packages RENAME inserted_at TO created_at")
    execute("ALTER TABLE registries RENAME inserted_at TO created_at")
    execute("ALTER TABLE releases RENAME inserted_at TO created_at")
    execute("ALTER TABLE keys RENAME inserted_at TO created_at")
    execute("ALTER TABLE users RENAME inserted_at TO created_at")
  end
end
