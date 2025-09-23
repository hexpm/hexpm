defmodule Hexpm.RepoBase.Migrations.CreateOauthSessions do
  use Ecto.Migration

  def change do
    create table(:oauth_sessions) do
      add :name, :string
      add :revoked_at, :utc_datetime_usec
      add :last_use, :map

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :client_id,
          references(:oauth_clients, column: :client_id, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:oauth_sessions, [:user_id])
    create index(:oauth_sessions, [:client_id])
    create index(:oauth_sessions, [:revoked_at])

    alter table(:oauth_tokens) do
      remove :token_family_id
      remove :name
      add :session_id, references(:oauth_sessions, on_delete: :delete_all), null: false
    end

    drop_if_exists index(:oauth_tokens, [:token_family_id])
    create index(:oauth_tokens, [:session_id])
  end
end