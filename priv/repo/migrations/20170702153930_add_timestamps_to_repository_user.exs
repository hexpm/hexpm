defmodule Hexpm.Repo.Migrations.AddTimestampsToRepositoryUser do
  use Ecto.Migration

  def change() do
    alter table(:repository_users) do
      timestamps()
    end
  end
end
