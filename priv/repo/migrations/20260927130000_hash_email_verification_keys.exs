defmodule Hexpm.Repo.Migrations.HashEmailVerificationKeys do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      add :verification_key_hash, :binary
    end

    execute("""
    UPDATE emails SET verification_key_hash = sha256(convert_to(verification_key, 'UTF8'))
    WHERE verification_key IS NOT NULL
    """)

    alter table(:emails) do
      remove :verification_key
    end
  end

  def down do
    alter table(:emails) do
      add :verification_key, :string
      remove :verification_key_hash
    end
  end
end
