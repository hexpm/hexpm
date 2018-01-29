defmodule Hexpm.Repo.Migrations.AddSessionKeyToUsers do
  use Ecto.Migration

  def change() do
    alter table(:users) do
      add(:session_key, :string)
    end
  end
end
