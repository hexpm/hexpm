defmodule Hexpm.Repo.Migrations.KeepPackageReportsOfRemovedPackages do
  use Ecto.Migration

  def up do
    alter table(:package_reports) do
      add :package_data, :map
    end

    execute("""
    UPDATE package_reports AS r
    SET package_data = jsonb_build_object('name', p.name, 'repository', repo.name)
    FROM packages AS p
    JOIN repositories AS repo ON repo.id = p.repository_id
    WHERE p.id = r.package_id
    """)

    execute("ALTER TABLE package_reports DROP CONSTRAINT package_reports_package_id_fkey")

    alter table(:package_reports) do
      modify :package_data, :map, null: false
      modify :package_id, references(:packages, on_delete: :nilify_all), null: true
    end
  end

  def down do
    raise Ecto.MigrationError,
      message: "this migration is irreversible"
  end
end
