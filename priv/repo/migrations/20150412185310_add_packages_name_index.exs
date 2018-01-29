defmodule Hexpm.Repo.Migrations.AddPackagesNameIndex do
  use Ecto.Migration

  def up() do
    execute("CREATE INDEX packages_name ON packages (name)")
  end

  def down() do
    execute("DROP INDEX packages_name")
  end
end
