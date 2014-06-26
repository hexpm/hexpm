defmodule HexWeb.Repo.Migrations.AddPackageOwnersTable do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE package_owners (
        id serial PRIMARY KEY,
        package_id integer REFERENCES packages,
        owner_id integer REFERENCES users)",

      "CREATE INDEX ON package_owners (package_id)",

      "INSERT INTO package_owners (package_id, owner_id)
        SELECT id, owner_id FROM packages",

      "ALTER TABLE packages DROP owner_id" ]
  end

  def down do
    [ "ALTER TABLE packages ADD owner_id integer REFERENCES users",

      "UPDATE packages SET owner_id = package_owners.owner_id
        FROM package_owners
        WHERE package_owners.package_id = id",

      "DROP TABLE IF EXISTS package_owners" ]
  end
end
