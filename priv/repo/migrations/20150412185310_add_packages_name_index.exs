defmodule Hexpm.Repo.Migrations.AddPackagesNameIndex do
  use Ecto.Migration

  def up() do
    execute("CREATE INDEX IF NOT EXISTS packages_name ON packages (name)")
  end

  def down() do
    execute("DROP INDEX IF EXISTS packages_name")
  end
end
