defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnOrganizations do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:organizations, [:name]))
    create_if_not_exists(unique_index(:organizations, ["(lower(name))"]))
    create_if_not_exists(index(:organizations, [:name]))
  end

  def down do
    drop_if_exists(index(:organizations, [:name]))
    drop_if_exists(index(:organizations, [:_lower_name]))
    create_if_not_exists(unique_index(:organizations, [:name]))
  end
end
