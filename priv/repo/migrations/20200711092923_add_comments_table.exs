defmodule Hexpm.RepoBase.Migrations.AddCommentsTable do
  use Ecto.Migration

  def up do
    create table(:comments) do
      add(:text, :string, null: false)
      add(:author_id, references(:users), null: false)
      add(:report_id, references(:package_reports), null: false)

      timestamps()
    end

    create(index("comments", [:report_id]))
  end

  def down() do
    drop(table("comments"))
  end
end
