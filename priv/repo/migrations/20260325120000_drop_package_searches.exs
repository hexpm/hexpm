defmodule Hexpm.RepoBase.Migrations.DropPackageSearches do
  use Ecto.Migration

  def change do
    drop table(:package_searches)
  end
end
