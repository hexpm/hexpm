defmodule Hexpm.RepoBase.Migrations.AlterSessionColumnsToNonNullable do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      modify(:uuid, :uuid, unique: true, null: false)
      modify(:expires_at, :utc_datetime_usec, null: false)
      modify(:active, :boolean, default: false, null: false)
    end

    execute("ALTER TABLE SESSIONS ALTER COLUMN user_id set NOT NULL")
  end

  def down do
    alter table(:sessions) do
      modify(:uuid, :uuid, unique: true, null: true)
      modify(:expires_at, :utc_datetime_usec, null: true)
      modify(:active, :boolean, default: false, null: true)
    end

    execute("ALTER TABLE SESSIONS ALTER COLUMN user_id DROP NOT NULL")
  end
end
