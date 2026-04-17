defmodule Hexpm.Repo.Migrations.OptimizeDownloadsIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create(
      index(:downloads, [:package_id, :day],
        name: "downloads_package_id_day_idx",
        concurrently: true
      )
    )

    create(
      index(:downloads, [:release_id, :day],
        name: "downloads_release_id_day_idx",
        concurrently: true
      )
    )

    drop_if_exists(
      index(:downloads, [:package_id], name: "downloads_package_id_index", concurrently: true)
    )

    drop_if_exists(
      index(:downloads, [:release_id], name: "downloads_release_id_idx", concurrently: true)
    )
  end

  def down() do
    create(index(:downloads, [:package_id], concurrently: true))
    create(index(:downloads, [:release_id], name: "downloads_release_id_idx", concurrently: true))

    drop(
      index(:downloads, [:release_id, :day],
        name: "downloads_release_id_day_idx",
        concurrently: true
      )
    )

    drop(
      index(:downloads, [:package_id, :day],
        name: "downloads_package_id_day_idx",
        concurrently: true
      )
    )
  end
end
