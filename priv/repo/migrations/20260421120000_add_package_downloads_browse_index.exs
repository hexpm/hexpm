defmodule Hexpm.Repo.Migrations.AddPackageDownloadsBrowseIndex do
  use Ecto.Migration

  def up() do
    create_if_not_exists(
      index(
        :package_downloads,
        [:view, "downloads DESC NULLS LAST", :package_id],
        name: :package_downloads_view_downloads_package_id_idx
      )
    )
  end

  def down() do
    drop_if_exists(
      index(
        :package_downloads,
        [:view, "downloads DESC NULLS LAST", :package_id],
        name: :package_downloads_view_downloads_package_id_idx
      )
    )
  end
end
