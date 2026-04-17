defmodule Hexpm.Repo.Migrations.OptimizeDownloadsIndexes do
  use Ecto.Migration

  def up() do
    create(index(:downloads, [:package_id, :day], name: "downloads_package_id_day_idx"))
    create(index(:downloads, [:release_id, :day], name: "downloads_release_id_day_idx"))

    execute("DROP INDEX IF EXISTS downloads_package_id_index")
    execute("DROP INDEX IF EXISTS downloads_release_id_idx")
  end

  def down() do
    create(index(:downloads, [:package_id]))
    execute("CREATE INDEX downloads_release_id_idx ON downloads (release_id)")

    drop(index(:downloads, [:release_id, :day], name: "downloads_release_id_day_idx"))
    drop(index(:downloads, [:package_id, :day], name: "downloads_package_id_day_idx"))
  end
end
