defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnOrganizations do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:organizations, [:name]))
    create(unique_index(:organizations, ["(lower(name))"]))
    create(index(:organizations, [:name]))
  end

  def down do
    drop_if_exists(index(:organizations, [:name]))
    drop_if_exists(index(:organizations, [:_lower_name]))
    create(unique_index(:organizations, [:name]))
  end
end
