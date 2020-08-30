defmodule Hexpm.RepoBase.Migrations.AddCommentsTable do
  use Ecto.Migration

  def up do
    create table(:package_report_comments) do
      add(:text, :text, null: false)
      add(:author_id, references(:users), null: false)
      add(:package_report_id, references(:package_reports), null: false)

      timestamps()
    end

    create(index("package_report_comments", [:package_report_id]))
  end

  def down() do
    drop(table("package_report_comments"))
  end
end
