defmodule Hexpm.RepoBase.Migrations.ImprovePackageNameIndex do
  use Ecto.Migration

  def up do
    create(unique_index(:packages, [:repository_id, "name text_pattern_ops"]))
    drop(unique_index(:packages, [:repository_id, :name]))

    execute("DROP MATERIALIZED VIEW release_downloads")

    execute("""
      CREATE MATERIALIZED VIEW release_downloads (
        package_id,
        release_id,
        downloads) AS
          SELECT package_id, release_id, SUM(downloads)
          FROM downloads
          GROUP BY package_id, release_id
    """)

    execute("CREATE UNIQUE INDEX ON release_downloads (release_id)")
  end

  def down do
    create(unique_index(:packages, [:repository_id, :name]))
    drop(unique_index(:packages, [:repository_id, "name text_pattern_ops"]))

    execute("DROP MATERIALIZED VIEW release_downloads")

    execute("""
      CREATE MATERIALIZED VIEW release_downloads (
        release_id,
        downloads) AS
          SELECT release_id, SUM(downloads)
          FROM downloads
          GROUP BY release_id
    """)

    execute("CREATE UNIQUE INDEX ON release_downloads (release_id)")
  end
end
