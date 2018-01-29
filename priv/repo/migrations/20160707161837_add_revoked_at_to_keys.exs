defmodule Hexpm.Repo.Migrations.AddRevokedAtToKeys do
  use Ecto.Migration

  def up() do
    alter table(:keys) do
      add(:revoked_at, :timestamp)
    end

    execute("ALTER TABLE keys DROP CONSTRAINT keys_user_id_name_key")

    execute(
      "ALTER TABLE keys ADD CONSTRAINT keys_user_id_name_revoked_at_key UNIQUE (user_id, name, revoked_at)"
    )
  end

  def down() do
    execute("ALTER TABLE keys DROP CONSTRAINT keys_user_id_name_revoked_at_key")
    execute("ALTER TABLE keys ADD CONSTRAINT keys_user_id_name_key UNIQUE (user_id, name)")

    alter table(:keys) do
      remove(:revoked_at)
    end
  end
end
