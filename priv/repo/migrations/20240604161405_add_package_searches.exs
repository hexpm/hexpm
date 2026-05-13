defmodule Hexpm.RepoBase.Migrations.AddPackageSearches do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:package_searches) do
      add(:package_id, references(:packages))
      add(:term, :text, null: false)
      add(:frequency, :integer, default: 1)
      timestamps()
    end

    create_if_not_exists(unique_index(:package_searches, [:term]))
  end
end
