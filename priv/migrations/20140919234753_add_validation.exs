defmodule HexWeb.Repo.Migrations.AddValidation do
  use Ecto.Migration

  def up do
    "ALTER TABLE users
      ADD COLUMN confirmed boolean,
      ADD COLUMN confirmation_key text"
  end

  def down do
    "ALTER TABLE users
      DROP COLUMN IF EXISTS confirmed
      DROP COLUMN IF EXISTS confirmation_key"
  end
end
