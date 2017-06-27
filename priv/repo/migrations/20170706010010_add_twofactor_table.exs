defmodule Hexpm.Repo.Migrations.AddTwofactorTable do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE twofactor_type AS ENUM ('disabled', 'totp')"

    create table(:twofactor) do
      add :type, :twofactor_type, null: false
      add :enabled, :boolean
      add :data, :map
      add :user_id, references(:users)

      timestamps()
    end

    create index(:twofactor, [:user_id])
  end

  def down do
    drop table(:twofactor)
    execute "DROP TYPE twofactor_type"
  end
end


