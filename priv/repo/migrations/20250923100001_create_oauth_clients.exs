defmodule Hexpm.RepoBase.Migrations.CreateOauthClients do
  use Ecto.Migration

  def change do
    create table(:oauth_clients, primary_key: false) do
      add :client_id, :binary_id, primary_key: true
      add :client_secret, :string
      add :name, :string, null: false
      add :client_type, :string, null: false
      add :allowed_grant_types, {:array, :string}
      add :redirect_uris, {:array, :string}
      add :allowed_scopes, {:array, :string}

      timestamps()
    end
  end
end