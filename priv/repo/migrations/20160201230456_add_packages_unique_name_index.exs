defmodule Hexpm.Repo.Migrations.AddPackagesUniqueNameIndex do
  use Ecto.Migration

  def up() do
    execute("DROP INDEX packages_name")
    execute("DROP INDEX users_username_index")

    execute("CREATE UNIQUE INDEX ON packages (name)")
    execute("CREATE UNIQUE INDEX ON users (username)")
  end

  def down() do
    execute("DROP INDEX packages_name_idx")
    execute("DROP INDEX users_username_idx")
  end
end
