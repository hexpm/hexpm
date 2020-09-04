defmodule Hexpm.RepoBase.Migrations.AlterSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add(:user_id, references(:users))
      add(:uuid, :uuid, unique: true)
      add(:expires_at, :utc_datetime_usec)
      add(:active, :boolean, default: false)
    end

    rename(table(:sessions), :token, to: :token_hash)
    create(unique_index(:sessions, [:token_hash]))
    create(unique_index(:sessions, [:uuid]))
    drop(index(:sessions, ["((data->>'user_id')::integer)"]))
  end
end
