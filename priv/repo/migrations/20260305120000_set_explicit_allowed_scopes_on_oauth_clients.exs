defmodule Hexpm.RepoBase.Migrations.SetExplicitAllowedScopesOnOauthClients do
  use Ecto.Migration

  def up do
    execute """
    UPDATE oauth_clients
    SET allowed_scopes = ARRAY['api', 'api:read', 'api:write', 'repositories']
    WHERE allowed_scopes IS NULL
    """

    alter table(:oauth_clients) do
      modify :allowed_scopes, {:array, :string}, null: false
    end
  end

  def down do
    alter table(:oauth_clients) do
      modify :allowed_scopes, {:array, :string}, null: true
    end
  end
end
