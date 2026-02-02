defmodule Hexpm.RepoBase.Migrations.AddRefreshTokenHashToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :refresh_token_hash, :text
    end

    create unique_index(:oauth_tokens, [:refresh_token_hash],
             where: "refresh_token_hash IS NOT NULL"
           )
  end
end
