defmodule Hexpm.Repo.Migrations.AllowNullPasswordForUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :password, :text, null: true
    end
  end
end
