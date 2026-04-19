defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnRepositories do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:repositories, [:name]))
    create_if_not_exists(unique_index(:repositories, ["(lower(name))"]))
    create_if_not_exists(index(:repositories, [:name]))
  end

  def down do
    drop_if_exists(index(:repositories, [:name]))
    drop_if_exists(index(:repositories, [:_lower_name]))
    create_if_not_exists(unique_index(:repositories, [:name]))
  end
end
