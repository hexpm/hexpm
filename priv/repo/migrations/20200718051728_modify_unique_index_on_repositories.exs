defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnRepositories do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:repositories, [:name]))
    create(unique_index(:repositories, ["(lower(name))"]))
    create(index(:repositories, [:name]))
  end

  def down do
    drop_if_exists(index(:repositories, [:name]))
    drop_if_exists(index(:repositories, [:_lower_name]))
    create(unique_index(:repositories, [:name]))
  end
end
