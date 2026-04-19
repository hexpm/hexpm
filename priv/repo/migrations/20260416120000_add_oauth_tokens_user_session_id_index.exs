defmodule Hexpm.RepoBase.Migrations.AddOauthTokensUserSessionIdIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:oauth_tokens, [:user_session_id], where: "revoked_at IS NULL")
  end
end
