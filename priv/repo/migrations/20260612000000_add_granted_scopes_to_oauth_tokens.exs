defmodule Hexpm.RepoBase.Migrations.AddGrantedScopesToOauthTokens do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      add(:granted_scopes, {:array, :string}, default: [], null: false)
    end

    execute("UPDATE oauth_tokens SET granted_scopes = scopes")
  end

  def down do
    alter table(:oauth_tokens) do
      remove(:granted_scopes)
    end
  end
end
