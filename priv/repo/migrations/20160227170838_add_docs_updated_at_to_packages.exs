defmodule Hexpm.Repo.Migrations.AddDocsRootUpdatedAtToPackages do
  use Ecto.Migration

  def up() do
    alter table(:packages) do
      add(:docs_updated_at, :naive_datetime, null: true)
    end

    execute("""
      UPDATE packages SET docs_updated_at = (
        SELECT MAX(updated_at) FROM releases
        WHERE has_docs = true
        AND packages.id = releases.package_id
        GROUP BY package_id
      )
    """)
  end

  def down() do
    alter table(:packages) do
      remove(:docs_updated_at)
    end
  end
end
