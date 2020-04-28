defmodule Hexpm.RepoBase.Migrations.AddShortUrlsTable do
  use Ecto.Migration

  def change do
    create table(:short_urls) do
      add(:url, :text, null: false)
      add(:short_code, :string, null: false)
      timestamps(updated_at: false)
    end

    create(index(:short_urls, [:url]))
    create(unique_index(:short_urls, [:short_code]))
  end
end
