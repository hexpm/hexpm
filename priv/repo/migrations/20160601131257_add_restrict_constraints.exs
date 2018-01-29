defmodule Hexpm.Repo.Migrations.AddRestrictConstraints do
  use Ecto.Migration

  def up() do
    execute("ALTER TABLE releases       DROP CONSTRAINT IF EXISTS releases_package_id_fkey")

    execute(
      "ALTER TABLE requirements   DROP CONSTRAINT IF EXISTS requirements_dependency_id_fkey"
    )

    execute("""
      ALTER TABLE releases
        ADD CONSTRAINT releases_package_id_fkey
          FOREIGN KEY (package_id) REFERENCES packages ON DELETE RESTRICT
    """)

    execute("""
      ALTER TABLE requirements
        ADD CONSTRAINT requirements_dependency_id_fkey
          FOREIGN KEY (dependency_id) REFERENCES packages ON DELETE RESTRICT
    """)
  end

  def down() do
    execute("ALTER TABLE releases       DROP CONSTRAINT IF EXISTS releases_package_id_fkey")

    execute(
      "ALTER TABLE requirements   DROP CONSTRAINT IF EXISTS requirements_dependency_id_fkey"
    )

    execute("""
      ALTER TABLE releases
        ADD CONSTRAINT releases_package_id_fkey
          FOREIGN KEY (package_id) REFERENCES packages
    """)

    execute("""
      ALTER TABLE requirements
        ADD CONSTRAINT requirements_dependency_id_fkey
          FOREIGN KEY (dependency_id) REFERENCES packages
    """)
  end
end
