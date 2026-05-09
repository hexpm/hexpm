defmodule Hexpm.Repo.Migrations.AddRepositoriesTable do
  use Ecto.Migration

  def up() do
    create_if_not_exists table(:repositories) do
      add(:name, :string, null: false)
      add(:public, :boolean, null: false, default: false)
      timestamps()
    end

    execute(
      "INSERT INTO repositories (name, public, inserted_at, updated_at) VALUES ('hexpm', true, now(), now())"
    )

    alter table(:packages) do
      add(:repository_id, references(:repositories), default: 1)
    end

    alter table(:packages) do
      modify(:repository_id, :integer, null: false, default: nil)
    end

    create_if_not_exists(unique_index(:repositories, [:name]))
    create_if_not_exists(index(:repositories, [:public]))
    create_if_not_exists(unique_index(:packages, [:repository_id, :name]))
    drop_if_exists(index(:packages, [:name], name: "packages_name_idx"))
  end

  def down() do
    alter table(:packages) do
      remove(:repository_id)
    end

    drop_if_exists(table(:repositories))

    create_if_not_exists(unique_index(:packages, [:name], name: "packages_name_idx"))
  end
end
