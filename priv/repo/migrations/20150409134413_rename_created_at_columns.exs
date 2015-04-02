defmodule HexWeb.Repo.Migrations.RenameCreatedAtColumns do
  use Ecto.Migration

  def up do
    [ "ALTER TABLE packages RENAME created_at TO inserted_at",
      "ALTER TABLE registries RENAME created_at TO inserted_at",
      "ALTER TABLE releases RENAME created_at TO inserted_at",
      "ALTER TABLE keys RENAME created_at TO inserted_at",
      "ALTER TABLE users RENAME created_at TO inserted_at" ]
  end

  def down do
    [ "ALTER TABLE packages RENAME inserted_at TO created_at",
      "ALTER TABLE registries RENAME inserted_at TO created_at",
      "ALTER TABLE releases RENAME inserted_at TO created_at",
      "ALTER TABLE keys RENAME inserted_at TO created_at",
      "ALTER TABLE users RENAME inserted_at TO created_at" ]
  end
end
