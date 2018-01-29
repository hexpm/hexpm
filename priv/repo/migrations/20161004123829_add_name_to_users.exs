defmodule Hexpm.Repo.Migrations.AddNameToUsers do
  use Ecto.Migration

  def change() do
    alter table(:users) do
      add(:full_name, :text)
    end
  end
end
