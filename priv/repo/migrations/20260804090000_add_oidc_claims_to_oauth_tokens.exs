defmodule Hexpm.Repo.Migrations.AddOidcClaimsToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :oidc_claims, :map
    end
  end
end
