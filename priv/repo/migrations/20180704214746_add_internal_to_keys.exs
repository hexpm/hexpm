defmodule Hexpm.Repo.Migrations.AddInternalToKeys do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE keys ALTER name DROP NOT NULL")

    alter table(:keys) do
      add(:public, :boolean, default: true, null: false)
      add(:revoke_at, :timestamp)
    end

    create_if_not_exists(index(:keys, [:name]))
    create_if_not_exists(index(:keys, [:revoked_at]))
    create_if_not_exists(index(:keys, [:revoke_at]))
    create_if_not_exists(index(:keys, [:public]))
  end

  def down do
    execute("ALTER TABLE keys ALTER name SET NOT NULL")

    alter table(:keys) do
      remove(:public)
      remove(:revoke_at)
    end

    drop_if_exists(index(:keys, [:name]))
    drop_if_exists(index(:keys, [:revoked_at]))
  end
end
