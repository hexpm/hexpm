defmodule Hexpm.Repo.Migrations.AddPackageDownloadsBrowseIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    create_if_not_exists(
      index(
        :package_downloads,
        [:view, "downloads DESC NULLS LAST", :package_id],
        name: :package_downloads_view_downloads_package_id_idx,
        concurrently: true
      )
    )
  end

  def down() do
    drop_if_exists(
      index(
        :package_downloads,
        [:view, "downloads DESC NULLS LAST", :package_id],
        name: :package_downloads_view_downloads_package_id_idx,
        concurrently: true
      )
    )
  end
end
