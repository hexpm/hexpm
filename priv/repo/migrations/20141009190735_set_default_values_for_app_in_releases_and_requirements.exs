defmodule Hexpm.Repo.Migrations.SetDefaultValuesForAppInReleasesAndRequirements do
  use Ecto.Migration

  def up() do
    execute("""
      UPDATE releases AS r
        SET app = p.name
        FROM packages AS p
        WHERE r.app IS NULL AND p.id = r.package_id
    """)

    execute("""
      UPDATE requirements AS r
        SET app = p.name
        FROM packages AS p
        WHERE r.app IS NULL AND p.id = r.dependency_id
    """)
  end

  def down() do
    execute("""
      UPDATE releases
        SET app = NULL
    """)

    execute("""
      UPDATE requirements
        SET app = NULL
    """)
  end
end
