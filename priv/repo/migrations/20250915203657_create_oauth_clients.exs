defmodule Hexpm.RepoBase.Migrations.CreateOauthClients do
  use Ecto.Migration

  def change do
    create table(:oauth_clients) do
      add :client_id, :string, null: false
      add :client_secret, :string
      add :name, :string, null: false
      add :client_type, :string, null: false
      add :allowed_grant_types, {:array, :string}, null: false
      add :redirect_uris, {:array, :string}
      add :allowed_scopes, {:array, :string}

      timestamps()
    end

    create unique_index(:oauth_clients, [:client_id])
    create index(:oauth_clients, [:client_type])
  end
end
