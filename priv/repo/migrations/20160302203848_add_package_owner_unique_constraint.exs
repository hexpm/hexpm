defmodule Hexpm.Repo.Migrations.AddPackageOwnerUniqueConstraint do
  use Ecto.Migration

  def up() do
    execute("""
    ALTER TABLE package_owners
      ADD CONSTRAINT package_owners_unique UNIQUE (package_id, owner_id)
    """)
  end

  def down() do
    execute("""
    ALTER TABLE package_owners
      DROP CONSTRAINT package_owners_unique
    """)
  end
end
