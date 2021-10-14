defmodule Hexpm.RepoBase.Migrations.AddWebAuthRequestsTable do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add(:device_code, :string)
      add(:user_code, :string)
      add(:scope, :string)
      add(:verified, :boolean)
      add(:key, :map)
    end
  end
end
