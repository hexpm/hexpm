defmodule Hexpm.Repo.Migrations.CreateShortURLTargets do
  use Ecto.Migration

  def change do
    create table(:short_url_targets) do
      add :url, :text, null: false
      add :url_hash, :binary, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:short_url_targets, [:url_hash])

    alter table(:short_urls) do
      add :target_id, references(:short_url_targets, on_delete: :restrict)
      modify :url, :text, null: true, from: {:text, null: false}
    end

    create index(:short_urls, [:target_id])
  end
end
