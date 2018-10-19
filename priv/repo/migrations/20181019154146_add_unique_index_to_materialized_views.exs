defmodule Hexpm.RepoBase.Migrations.AddUniqueIndexToMaterializedViews do
  use Ecto.Migration

  def change do
    execute("DROP INDEX package_dependants_name_idx")
    execute("CREATE UNIQUE INDEX ON package_dependants (name, dependant_id)")

    execute("DROP INDEX package_downloads_package_id_idx")
    execute("CREATE UNIQUE INDEX ON package_downloads (package_id, view)")

    execute("DROP INDEX release_downloads_release_id_idx")
    execute("CREATE UNIQUE INDEX ON release_downloads (release_id)")
  end
end
