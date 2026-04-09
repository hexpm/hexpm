defmodule Hexpm.RepoBase.Migrations.RequireAllowedGrantTypesOnOauthClients do
  use Ecto.Migration

  def up do
    execute """
    UPDATE oauth_clients
    SET allowed_grant_types = ARRAY[
      'authorization_code',
      'urn:ietf:params:oauth:grant-type:device_code',
      'refresh_token',
      'client_credentials'
    ]
    WHERE allowed_grant_types IS NULL
    """

    alter table(:oauth_clients) do
      modify :allowed_grant_types, {:array, :string}, null: false
    end
  end

  def down do
    alter table(:oauth_clients) do
      modify :allowed_grant_types, {:array, :string}, null: true
    end
  end
end
