defmodule Hexpm.RepoBase.Migrations.AddPackageReportsTable do
  use Ecto.Migration

  def up() do
    create table(:package_reports) do
      add(:description, :text, null: false)
      add(:state, :string, null: false)
      add(:package_id, references(:packages), null: false)
      add(:author_id, references(:users), null: false)

      timestamps()
    end

    create(index("package_reports", [:package_id]))
  end

  def down() do
    drop(table("package_reports"))
  end
end
