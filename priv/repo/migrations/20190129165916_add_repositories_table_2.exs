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
    VALUES ('hexpm', true, 1, now(), now())
    """)

    execute("""
    INSERT INTO repositories (name, public, organization_id, inserted_at, updated_at)
    SELECT name, public, id, now(), now() FROM organizations WHERE id != 1 ORDER BY id
    """)

    alter table(:packages) do
      add(:repository_id, references(:repositories))
    end

    execute("""
    UPDATE packages SET repository_id = repositories.id
    FROM repositories WHERE packages.organization_id = repositories.organization_id
    """)

    alter table(:packages) do
      modify(:repository_id, :integer, null: false)
      remove(:organization_id)
    end

    alter table(:reserved_packages) do
      add(:repository_id, references(:repositories))
    end

    execute("""
    UPDATE reserved_packages SET repository_id = repositories.id
    FROM repositories WHERE reserved_packages.organization_id = repositories.organization_id
    """)

    alter table(:reserved_packages) do
      modify(:repository_id, :integer, null: false)
      remove(:organization_id)
    end

    execute("UPDATE organizations SET billing_active = true WHERE id = 1")

    create(unique_index(:repositories, [:name]))
    create(index(:repositories, [:public]))
    create(unique_index(:packages, [:repository_id, :name]))
    create(unique_index(:reserved_packages, [:repository_id, :name, :version]))
  end

  def down() do
    alter table(:packages) do
      add(:organization_id, references(:organizations))
    end

    execute("""
    UPDATE packages SET organization_id = repositories.organization_id
    FROM repositories WHERE packages.repository_id = repositories.id
    """)

    alter table(:packages) do
      remove(:repository_id)
    end

    alter table(:reserved_packages) do
      add(:organization_id, references(:organizations))
    end

    execute("""
    UPDATE reserved_packages SET organization_id = repositories.organization_id
    FROM repositories WHERE reserved_packages.repository_id = repositories.id
    """)

    alter table(:reserved_packages) do
      modify(:organization_id, :integer, null: false)
      remove(:repository_id)
    end

    execute("UPDATE organizations SET billing_active = false WHERE id = 1")

    drop(table(:repositories))
    create(unique_index(:packages, [:organization_id, :name]))
    create(unique_index(:reserved_packages, [:organization_id, :name, :version]))
  end
end
