defmodule HexWeb.Repo.Migrations.ResetKey do
  use Ecto.Migration

  def up do
    "ALTER TABLE users
      ADD COLUMN reset_key text,
      ADD COLUMN reset_expiry timestamp"
  end

  def down do
    "ALTER TABLE users
      DROP COLUMN IF EXISTS reset_key,
      DROP COLUMN IF EXISTS reset_expiry"
  end
end
