defmodule Hexpm.RepoBase.Migrations.AddShortUrlsTable do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:short_urls) do
      add(:url, :text, null: false)
      add(:short_code, :string, null: false)
      timestamps(updated_at: false)
    end

    create_if_not_exists(index(:short_urls, [:url]))
    create_if_not_exists(unique_index(:short_urls, [:short_code]))
  end
end
