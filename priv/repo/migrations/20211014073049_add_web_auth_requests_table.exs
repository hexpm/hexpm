defmodule Hexpm.RepoBase.Migrations.AddWebAuthRequestsTable do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add(:device_code, :string, null: false)
      add(:user_code, :string, null: false)
      add(:scope, :string, null: false)
      add(:verified, :boolean, null: false)
      add(:user_id, :integer, null: false)
      add(:audit, :string, null: false)
    end
  end
end
