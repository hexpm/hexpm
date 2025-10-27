defmodule Hexpm.RepoBase.Migrations.AddKeyIdToUserSessions do
  use Ecto.Migration

  def change do
    alter table(:user_sessions) do
      add :key_id, references(:keys, on_delete: :nilify_all)
    end

    create index(:user_sessions, [:key_id])
  end
end
