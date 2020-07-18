defmodule Hexpm.RepoBase.Migrations.ModifyUniqueIndexOnRepositories do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:repositories, [:name]))
    create(unique_index(:repositories, ["(lower(name))"], name: :repositories_name_index))
  end

  def down do
    drop_if_exists(index(:repositories, [:name]))
    create(unique_index(:repositories, [:name]))
  end
end
