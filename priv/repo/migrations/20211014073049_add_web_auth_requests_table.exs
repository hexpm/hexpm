defmodule Hexpm.RepoBase.Migrations.AddWebAuthRequestsTable do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add(:device_code, :string, null: false)
      add(:user_code, :string, null: false)
      add(:key_name, :string, null: false)
      add(:verified, :boolean, null: false)
      add(:user_id, references(:users))
      add(:audit, :string)
    end

    create(unique_index(:requests, [:user_code, :device_code]))
  end
end
