defmodule Hexpm.RepoBase.Migrations.AddDownloadsPackageId do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      add(:package_id, references(:packages, on_delete: :delete_all))
    end

    create(index(:downloads, [:package_id]))
  end
end

# Migration query:
# UPDATE downloads d
# SET package_id = r.package_id
# FROM releases r
# WHERE r.id = d.release_id
