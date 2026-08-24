defmodule Hexpm.Repo.Migrations.DropSessionsTable do
  use Ecto.Migration

  def up() do
    drop_if_exists(table(:sessions))
  end

  def down() do
    create_if_not_exists table(:sessions) do
      add(:token, :binary, null: false)
      add(:data, :jsonb, null: false)

      timestamps()
    end
  end
end
