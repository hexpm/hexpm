defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnOrganizations do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:organizations, [:name]))
    create(unique_index(:organizations, ["(lower(name))"], name: :organizations_name_index))
  end

  def down do
    drop_if_exists(index(:organizations, [:name]))
    create(unique_index(:organizations, [:name]))
  end
end
