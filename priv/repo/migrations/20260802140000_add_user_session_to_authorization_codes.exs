defmodule Hexpm.RepoBase.Migrations.AddUserSessionToAuthorizationCodes do
  use Ecto.Migration

  def change do
    alter table(:authorization_codes) do
      add(:user_session_id, references(:user_sessions, on_delete: :nilify_all))
    end

    create(index(:authorization_codes, [:user_session_id]))
  end
end
