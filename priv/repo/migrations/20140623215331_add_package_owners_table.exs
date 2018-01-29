defmodule Hexpm.Repo.Migrations.AddPackageOwnersTable do
  use Ecto.Migration

  def up() do
    execute("""
      CREATE TABLE package_owners (
        id serial PRIMARY KEY,
        package_id integer REFERENCES packages,
        owner_id integer REFERENCES users)
    """)

    execute("CREATE INDEX ON package_owners (package_id)")

    execute("""
      INSERT INTO package_owners (package_id, owner_id)
        SELECT id, owner_id FROM packages
    """)

    execute("ALTER TABLE packages DROP owner_id")
  end

  def down() do
    execute("ALTER TABLE packages ADD owner_id integer REFERENCES users")

    execute("""
      UPDATE packages SET owner_id = package_owners.owner_id
        FROM package_owners
        WHERE package_owners.package_id = id
    """)

    execute("DROP TABLE IF EXISTS package_owners")
  end
end
