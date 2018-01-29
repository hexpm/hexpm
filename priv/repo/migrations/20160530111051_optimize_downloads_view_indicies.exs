defmodule Hexpm.Repo.Migrations.OptimizeDownloadsViewIndicies do
  use Ecto.Migration

  def up() do
    execute("DROP INDEX package_downloads_view_downloads_idx")
    execute("CREATE INDEX ON package_downloads (view)")
    execute("CREATE INDEX ON package_downloads (downloads DESC NULLS LAST)")
  end

  def down() do
    execute("DROP INDEX package_downloads_view_idx")
    execute("DROP INDEX package_downloads_downloads_idx")
    execute("CREATE INDEX ON package_downloads (view, downloads)")
  end
end
