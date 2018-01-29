defmodule Hexpm.Repo.Migrations.AddConfirmationToUsers do
  use Ecto.Migration

  def up() do
    execute("""
      ALTER TABLE users
        ADD COLUMN confirmed boolean DEFAULT false,
        ADD COLUMN confirmation_key text
    """)

    execute("""
      UPDATE users
        SET confirmed = true
    """)
  end

  def down() do
    execute("""
      ALTER TABLE users
        DROP COLUMN IF EXISTS confirmed
        DROP COLUMN IF EXISTS confirmation_key
    """)
  end
end
