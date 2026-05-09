defmodule Hexpm.Repo.Migrations.AddSessionsTable do
  use Ecto.Migration

  def up() do
    create_if_not_exists table(:sessions) do
      add(:token, :binary, null: false)
      add(:data, :jsonb, null: false)

      timestamps()
    end

    create_if_not_exists(index(:sessions, ["((data->>'user_id')::integer)"]))

    alter table(:users) do
      remove(:session_key)
    end
  end

  def down() do
    drop_if_exists(table(:sessions))

    alter table(:users) do
      add(:session_key, :string)
    end
  end
end
