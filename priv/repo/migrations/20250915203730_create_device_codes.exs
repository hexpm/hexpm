defmodule Hexpm.RepoBase.Migrations.CreateDeviceCodes do
  use Ecto.Migration

  def change do
    create table(:device_codes) do
      add :device_code, :string, null: false
      add :user_code, :string, null: false
      add :verification_uri, :string, null: false
      add :verification_uri_complete, :string

      add :client_id,
          references(:oauth_clients, column: :client_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :expires_at, :utc_datetime_usec, null: false
      add :interval, :integer, null: false
      add :status, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []

      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:device_codes, [:device_code])
    create unique_index(:device_codes, [:user_code])
    create index(:device_codes, [:expires_at])
    create index(:device_codes, [:status])
    create index(:device_codes, [:user_id])
  end
end
