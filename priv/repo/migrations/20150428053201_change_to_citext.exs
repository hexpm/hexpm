defmodule Hexpm.Repo.Migrations.ChangeToCitext do
  use Ecto.Migration

  def up() do
    execute("CREATE EXTENSION citext")

    drop(index(:users, [:username], name: :users_lower_idx))

    alter table(:users) do
      modify(:username, :citext)
    end

    alter table(:packages) do
      modify(:name, :citext)
    end

    create(index(:users, [:username]))
  end

  def down() do
    drop(index(:users, [:username]))

    alter table(:users) do
      modify(:username, :text)
    end

    alter table(:packages) do
      modify(:name, :text)
    end

    create(index(:users, ["lower(username)"], name: :users_lower_idx))

    execute("DROP EXTENSION IF EXISTS citext")
  end
end
