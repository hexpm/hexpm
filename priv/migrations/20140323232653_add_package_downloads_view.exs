defmodule HexWeb.Repo.Migrations.AddPackageDownloadsView do
  use Ecto.Migration

  def up do
    [ "CREATE TYPE calendar_view AS ENUM ('day', 'week', 'all')",

      "CREATE MATERIALIZED VIEW package_downloads (
        package_id,
        view,
        downloads) AS
          SELECT r.package_id, v.view, SUM(d.downloads)
          FROM downloads AS d
          JOIN releases AS r ON r.id = d.release_id
          CROSS JOIN (VALUES ('day'), ('week'), ('all')) AS v(view)
          WHERE CASE
                  WHEN v.view='day'
                    THEN d.day = current_date - interval '1 day'
                  WHEN v.view='week'
                    THEN d.day BETWEEN current_date - interval '8 days' AND
                                       current_date - interval '1 day'
                  WHEN v.view='all'
                    THEN true
                END
          GROUP BY r.package_id, v.view",

      "CREATE INDEX ON package_downloads (package_id)",
      "CREATE INDEX ON package_downloads (view, downloads)" ]
  end

  def down do
    [ "DROP TABLE IF EXISTS package_downloads",
      "DROP TYPE IF EXISTS calendar_view" ]
  end
end
