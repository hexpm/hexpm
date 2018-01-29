defmodule Hexpm.Repo.Migrations.AddReleaseDownloadsView do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE MATERIALIZED VIEW release_downloads (
        release_id,
        downloads) AS
          SELECT d.release_id, SUM(d.downloads)
          FROM downloads AS d
          GROUP BY release_id
    """)

    execute("CREATE INDEX ON release_downloads (release_id)")
  end

  def down() do
    execute("DROP MATERIALIZED VIEW IF EXISTS release_downloads")
  end
end
