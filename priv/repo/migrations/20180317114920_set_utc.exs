defmodule Hexpm.Repo.Migrations.SetUtc do
  use Ecto.Migration

  def change do
    database_name = Keyword.fetch!(Hexpm.RepoBase.config(), :database)
    execute("ALTER DATABASE #{database_name} SET timezone TO 'UTC'")
  end
end
