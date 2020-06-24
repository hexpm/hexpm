defmodule Hexpm.RepoBase.Migrations.AddPackageReportsTable do
  use Ecto.Migration

  def up() do
    create table(:package_reports) do
      add(:description, :string)
      add(:state,       :string)
      add(:package_id,  references(:packages), null: false)
      add(:author_id,   references(:users), null: false)
      
      timestamps()
    end

    create index("package_reports", [:author_id])
  end

  def down() do
    drop table("package_reports")
  end
end
