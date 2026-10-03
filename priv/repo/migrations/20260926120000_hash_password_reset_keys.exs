defmodule Hexpm.Repo.Migrations.HashPasswordResetKeys do
  use Ecto.Migration

  def up do
    alter table(:password_resets) do
      add :key_hash, :binary
    end

    execute("UPDATE password_resets SET key_hash = sha256(convert_to(key, 'UTF8'))")

    alter table(:password_resets) do
      modify :key_hash, :binary, null: false
      remove :key
    end
  end

  def down do
    alter table(:password_resets) do
      add :key, :string
    end

    execute("DELETE FROM password_resets")

    alter table(:password_resets) do
      modify :key, :string, null: false
      remove :key_hash
    end
  end
end
