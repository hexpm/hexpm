defmodule Hexpm.Repo.Migrations.IndexReleasesBySemverSortKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create(
      index(:releases, [:package_id, "semver_sort_key DESC"],
        name: :releases_package_id_semver_sort_key_desc_index,
        concurrently: true
      )
    )

    create(
      index(:releases, [:package_id, "semver_stable DESC", "semver_sort_key DESC"],
        name: :releases_package_id_stable_semver_sort_key_desc_index,
        concurrently: true
      )
    )
  end

  def down do
    drop(
      index(:releases, [:package_id, "semver_stable DESC", "semver_sort_key DESC"],
        name: :releases_package_id_stable_semver_sort_key_desc_index,
        concurrently: true
      )
    )

    drop(
      index(:releases, [:package_id, "semver_sort_key DESC"],
        name: :releases_package_id_semver_sort_key_desc_index,
        concurrently: true
      )
    )
  end
end
