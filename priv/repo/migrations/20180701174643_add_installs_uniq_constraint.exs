defmodule Hexpm.Repo.Migrations.AddInstallsUniqConstraint do
  use Ecto.Migration

  def change do
    create(unique_index(:installs, [:hex]))
  end
end
