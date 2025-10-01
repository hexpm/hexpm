defmodule Hexpm.RepoBase.Migrations.CreateAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:authorization_codes) do
      add :code, :string, null: false
      add :redirect_uri, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      add :code_challenge, :string
      add :code_challenge_method, :string

      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :client_id,
          references(:oauth_clients, column: :client_id, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:authorization_codes, [:code])
    create index(:authorization_codes, [:user_id])
    create index(:authorization_codes, [:client_id])
    create index(:authorization_codes, [:expires_at])
  end
end