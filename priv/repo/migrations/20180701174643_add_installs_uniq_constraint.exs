defmodule Hexpm.Repo.Migrations.AddInstallsUniqConstraint do
  use Ecto.Migration

  def change do
    create_if_not_exists(unique_index(:installs, [:hex]))
  end
end
