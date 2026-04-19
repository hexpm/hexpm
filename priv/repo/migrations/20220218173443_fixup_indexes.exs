defmodule Hexpm.RepoBase.Migrations.FixupIndexes do
  use Ecto.Migration

  def change do
    drop_if_exists(
      index(:package_downloads, [:view, :downloads], name: "package_downloads_view_downloads_idx")
    )

    drop_if_exists(unique_index(:repositories, ["(lower(name))"]))
    drop_if_exists(index(:repositories, [:name]))
    drop_if_exists(unique_index(:organizations, ["(lower(name))"]))
    drop_if_exists(index(:organizations, [:name]))
    drop_if_exists(unique_index(:packages, [:repository_id, "(lower(name))"]))
    drop_if_exists(index(:packages, [:repository_id, :name]))
    drop_if_exists(index(:keys, [:public]))
    drop_if_exists(index(:package_owners, [:package_id], name: "package_owners_package_id_idx"))

    create_if_not_exists(index(:package_downloads, [:view]))
    create_if_not_exists(index(:package_downloads, ["downloads DESC NULLS LAST"]))
    create_if_not_exists(unique_index(:repositories, [:name]))
    create_if_not_exists(unique_index(:organizations, [:name]))
    create_if_not_exists(unique_index(:packages, [:repository_id, :name]))
    create_if_not_exists(index(:packages, [:name]))
    create_if_not_exists(index(:audit_logs, [:inserted_at]))
    create_if_not_exists(index(:package_owners, [:user_id]))
  end
end
