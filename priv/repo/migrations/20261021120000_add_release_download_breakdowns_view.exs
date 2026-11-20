defmodule Hexpm.RepoBase.Migrations.AddReleaseDownloadBreakdownsView do
  use Ecto.Migration

  def up() do
    execute("""
    CREATE MATERIALIZED VIEW release_download_breakdowns AS
      SELECT d.package_id, d.release_id, v.view, SUM(d.downloads) AS downloads
      FROM downloads AS d
      CROSS JOIN (VALUES ('day'), ('week'), ('recent'), ('all')) AS v(view)
      WHERE CASE
              WHEN v.view='day'
                THEN d.day = CURRENT_DATE - interval '1 day'
              WHEN v.view='week'
                THEN d.day BETWEEN CURRENT_DATE - interval '7 days' AND
                                   CURRENT_DATE - interval '1 day'
              WHEN v.view='recent'
                THEN d.day BETWEEN CURRENT_DATE - interval '90 days' AND
                                   CURRENT_DATE - interval '1 day'
              WHEN v.view='all'
                THEN true
            END
      GROUP BY d.package_id, d.release_id, v.view
    """)

    execute("""
    CREATE UNIQUE INDEX release_download_breakdowns_release_id_view_idx
      ON release_download_breakdowns (release_id, view)
    """)
  end

  def down() do
    execute("DROP MATERIALIZED VIEW IF EXISTS release_download_breakdowns")
  end
end
