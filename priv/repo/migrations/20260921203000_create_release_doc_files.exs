defmodule Hexpm.Repo.Migrations.CreateReleaseDocFiles do
  use Ecto.Migration

  def change do
    create table(:release_doc_files, primary_key: false) do
      add :release_id, references(:releases, on_delete: :delete_all), primary_key: true
      add :files, :jsonb, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
