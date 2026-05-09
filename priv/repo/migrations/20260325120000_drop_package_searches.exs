defmodule Hexpm.RepoBase.Migrations.DropPackageSearches do
  use Ecto.Migration

  def change do
    drop_if_exists table(:package_searches)
  end
end
