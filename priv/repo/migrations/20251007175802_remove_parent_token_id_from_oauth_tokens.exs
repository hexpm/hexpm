defmodule Hexpm.RepoBase.Migrations.RemoveParentTokenIdFromOauthTokens do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      remove :parent_token_id
    end
  end

  def down do
    alter table(:oauth_tokens) do
      add :parent_token_id, references(:oauth_tokens, on_delete: :nothing)
    end
  end
end
