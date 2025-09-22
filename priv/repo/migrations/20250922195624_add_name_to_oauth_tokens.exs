defmodule Hexpm.RepoBase.Migrations.AddNameToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :name, :string
    end
  end
end