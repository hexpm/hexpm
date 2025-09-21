defmodule Hexpm.RepoBase.Migrations.CreateOauthTokens do
  use Ecto.Migration

  def up do
    create table(:oauth_tokens) do
      add :token_first, :string, null: false
      add :token_second, :string, null: false
      add :token_type, :string, null: false, default: "bearer"
      add :refresh_token_first, :string
      add :refresh_token_second, :string
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :client_id,
          references(:oauth_clients, column: :client_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :grant_type, :string, null: false
      add :grant_reference, :string

      add :parent_token_id, references(:oauth_tokens, on_delete: :nothing)
      add :token_family_id, :string

      timestamps()
    end

    create unique_index(:oauth_tokens, [:token_first, :token_second])
    create unique_index(:oauth_tokens, [:refresh_token_first, :refresh_token_second])
    create index(:oauth_tokens, [:token_first])
    create index(:oauth_tokens, [:refresh_token_first])
    create index(:oauth_tokens, [:user_id])
    create index(:oauth_tokens, [:client_id])
    create index(:oauth_tokens, [:expires_at])
    create index(:oauth_tokens, [:token_family_id])
  end

  def down do
    drop_if_exists table(:oauth_tokens)
  end
end
