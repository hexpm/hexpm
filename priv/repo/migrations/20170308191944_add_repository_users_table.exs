defmodule Hexpm.Repo.Migrations.AddRepositoryUsersTable do
  use Ecto.Migration

  def up() do
    execute("CREATE TYPE repository_user_role AS ENUM ('owner', 'admin', 'write', 'read')")

    create table(:repository_users) do
      add(:role, :repository_user_role, null: false)
      add(:repository_id, references(:repositories))
      add(:user_id, references(:users))
    end

    create(unique_index(:repository_users, [:repository_id, :user_id]))
    create(index(:repository_users, [:user_id]))
  end

  def down() do
    drop(table(:repository_users))
    execute("DROP TYPE repository_user_role")
  end
end
