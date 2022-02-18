defmodule Hexpm.RepoBase.Migrations.FixupIndexes do
  use Ecto.Migration

  def change do
    drop(
      index(:package_downloads, [:view, :downloads], name: "package_downloads_view_downloads_idx")
    )

    drop(unique_index(:repositories, ["(lower(name))"]))
    drop(index(:repositories, [:name]))
    drop(unique_index(:organizations, ["(lower(name))"]))
    drop(index(:organizations, [:name]))
    drop(unique_index(:packages, [:repository_id, "(lower(name))"]))
    drop(index(:packages, [:repository_id, :name]))
    drop(index(:keys, [:public]))
    drop(index(:package_owners, [:package_id], name: "package_owners_package_id_idx"))

    create(index(:package_downloads, [:view]))
    create(index(:package_downloads, ["downloads DESC NULLS LAST"]))
    create(unique_index(:repositories, [:name]))
    create(unique_index(:organizations, [:name]))
    create(unique_index(:packages, [:repository_id, :name]))
    create(index(:packages, [:name]))
    create(index(:audit_logs, [:inserted_at]))
    create(index(:package_owners, [:user_id]))
  end
end
