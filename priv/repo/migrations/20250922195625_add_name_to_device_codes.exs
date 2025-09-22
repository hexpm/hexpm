defmodule Hexpm.RepoBase.Migrations.AddNameToDeviceCodes do
  use Ecto.Migration

  def change do
    alter table(:device_codes) do
      add :name, :string
    end
  end
end