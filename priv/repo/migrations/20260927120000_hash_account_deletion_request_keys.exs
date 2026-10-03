defmodule Hexpm.Repo.Migrations.HashAccountDeletionRequestKeys do
  use Ecto.Migration

  def up do
    alter table(:account_deletion_requests) do
      add :key_hash, :binary
    end

    execute("UPDATE account_deletion_requests SET key_hash = sha256(convert_to(key, 'UTF8'))")

    alter table(:account_deletion_requests) do
      modify :key_hash, :binary, null: false
      remove :key
    end
  end

  def down do
    alter table(:account_deletion_requests) do
      add :key, :string
    end

    execute("DELETE FROM account_deletion_requests")

    alter table(:account_deletion_requests) do
      modify :key, :string, null: false
      remove :key_hash
    end
  end
end
