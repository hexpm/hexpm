defmodule HexWeb.Repo.Migrations.AddRevokedToKeys do
  use Ecto.Migration

  def change do
    alter table(:keys) do
      add :revoked_name, :text
      add :revoked_at, :timestamp
    end
    create index(:keys, [:revoked_at])
  end
end
