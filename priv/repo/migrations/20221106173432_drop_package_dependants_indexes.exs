defmodule Hexpm.RepoBase.Migrations.DropUnusedIndexes do
  use Ecto.Migration

  def up do
    drop(index(:sessions, ["((data->>'user_id')::integer)"]))
    drop(index(:short_urls, [:url]))

    execute("DROP INDEX package_dependants_name_idx")
    execute("DROP INDEX package_dependants_name_repo_idx")
  end

  def down do
    create(index(:sessions, ["((data->>'user_id')::integer)"]))
    create(index(:short_urls, [:url]))

    execute("CREATE INDEX ON package_dependants (name)")
    execute("CREATE INDEX ON package_dependants (name, repo)")
  end
end
