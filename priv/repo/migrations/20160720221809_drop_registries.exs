defmodule Hexpm.Repo.Migrations.DropRegistries do
  use Ecto.Migration

  def up() do
    drop_if_exists(table(:registries))
  end

  def down() do
    create_if_not_exists table(:registries) do
      add(:state, :string)
      add(:inserted_at, :datetime)
      add(:started_at, :datetime)
    end
  end
end
