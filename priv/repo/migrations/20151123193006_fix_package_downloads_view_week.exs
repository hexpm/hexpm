defmodule Hexpm.Repo.Migrations.FixPackageDownloadsViewWeek do
  use Ecto.Migration

  def up() do
    execute("DROP MATERIALIZED VIEW package_downloads")

    execute("""
      CREATE MATERIALIZED VIEW package_downloads (
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
                    THEN d.day BETWEEN current_date - interval '7 days' AND
                                       current_date - interval '1 day'
                  WHEN v.view='all'
                    THEN true
                END
          GROUP BY r.package_id, v.view
          UNION
          SELECT NULL, 'day', SUM(d.downloads)
          FROM downloads AS d
          WHERE d.day = current_date - interval '1 day'
          UNION
          SELECT NULL, 'week', SUM(d.downloads)
          FROM downloads AS d
          WHERE d.day BETWEEN current_date - interval '7 days' AND
                              current_date - interval '1 day'
          UNION
          SELECT NULL, 'all', SUM(d.downloads)
          FROM downloads AS d
    """)

    execute("CREATE INDEX ON package_downloads (package_id)")
    execute("CREATE INDEX ON package_downloads (view, downloads)")
  end

  def down() do
    execute("DROP MATERIALIZED VIEW package_downloads")

    execute("""
      CREATE MATERIALIZED VIEW package_downloads (
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
          GROUP BY r.package_id, v.view
          UNION
          SELECT NULL, 'day', SUM(d.downloads)
          FROM downloads AS d
          WHERE d.day = current_date - interval '1 day'
          UNION
          SELECT NULL, 'week', SUM(d.downloads)
          FROM downloads AS d
          WHERE d.day BETWEEN current_date - interval '8 days' AND
                              current_date - interval '1 day'
          UNION
          SELECT NULL, 'all', SUM(d.downloads)
          FROM downloads AS d
    """)

    execute("CREATE INDEX ON package_downloads (package_id)")
    execute("CREATE INDEX ON package_downloads (view, downloads)")
  end
end
