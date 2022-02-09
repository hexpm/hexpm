defmodule Hexpm.RepoBase.Migrations.AddWebAuthRequestsTable do
  use Ecto.Migration

  def change do
    create table(:web_auth_requests) do
      add(:device_code, :string, null: false)
      add(:user_code, :string, null: false)
      add(:key_name, :string, null: false)
      add(:verified, :boolean, null: false)
      add(:user_id, references(:users))
    end

    create(unique_index(:web_auth_requests, [:user_code]))
    create(unique_index(:web_auth_requests, [:device_code]))
  end
end
