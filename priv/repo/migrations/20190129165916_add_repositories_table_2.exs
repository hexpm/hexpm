defmodule Hexpm.RepoBase.Migrations.AddRepositoriesTable2 do
  use Ecto.Migration

  def up do
    create table(:repositories) do
      add(:name, :string, null: false)
      add(:public, :boolean, null: false, default: false)
      add(:organization_id, references(:organizations))
      timestamps()
    end

    execute("""
    INSERT INTO repositories (name, public, organization_id, inserted_at, updated_at)
    SELECT name, public, id, now(), now() FROM organizations ORDER BY id
    """)

    alter table(:packages) do
      add(:repository_id, references(:repositories))
    end

    execute("UPDATE packages SET repository_id = organization_id")

    alter table(:packages) do
      modify(:repository_id, :integer, null: false, default: nil)
      remove(:organization_id)
    end

    execute("ALTER TABLE reserved_packages RENAME organization_id TO repository_id")

    execute(
      "ALTER INDEX reserved_packages_organization_id_name_version_index RENAME TO reserved_packages_repository_id_name_version_index"
    )

    execute("""
    ALTER TABLE reserved_packages
      RENAME CONSTRAINT reserved_packages_organization_id_fkey TO reserved_packages_repository_id_fkey
    """)

    execute("UPDATE organizations SET billing_active = true WHERE id = 1")

    create(unique_index(:repositories, [:name]))
    create(index(:repositories, [:public]))
    create(unique_index(:packages, [:repository_id, :name]))
  end

  def down() do
    alter table(:packages) do
      add(:organization_id, references(:organizations))
    end

    execute("UPDATE packages SET organization_id = repository_id")

    alter table(:packages) do
      remove(:repository_id)
    end

    execute("ALTER TABLE reserved_packages RENAME repository_id TO organization_id")

    execute(
      "ALTER INDEX reserved_packages_repository_id_name_version_index RENAME TO reserved_packages_organization_id_name_version_index"
    )

    execute("""
    ALTER TABLE reserved_packages
      RENAME CONSTRAINT reserved_packages_repository_id_fkey TO reserved_packages_organization_id_fkey
    """)

    execute("UPDATE organizations SET billing_active = false WHERE id = 1")

    drop(table(:repositories))
  end
end
