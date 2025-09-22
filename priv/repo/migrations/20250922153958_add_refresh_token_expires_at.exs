defmodule Hexpm.RepoBase.Migrations.AddRefreshTokenExpiresAt do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :refresh_token_expires_at, :utc_datetime
    end

    create index(:oauth_tokens, [:refresh_token_expires_at])
  end
end