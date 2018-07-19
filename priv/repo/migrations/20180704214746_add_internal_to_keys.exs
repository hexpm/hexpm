defmodule Hexpm.Repo.Migrations.AddInternalToKeys do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE keys ALTER name DROP NOT NULL")

    alter table(:keys) do
      add(:public, :boolean, default: true, null: false)
      add(:revoke_at, :timestamp)
    end

    create(index("keys", [:name]))
    create(index("keys", [:revoked_at]))
    create(index("keys", [:revoke_at]))
    create(index("keys", [:public]))
  end

  def down do
    execute("ALTER TABLE keys ALTER name SET NOT NULL")

    alter table(:keys) do
      remove(:public)
      remove(:revoke_at)
    end

    drop(index("keys", [:name]))
    drop(index("keys", [:revoked_at]))
  end
end
