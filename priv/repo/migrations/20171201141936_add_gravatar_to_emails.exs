defmodule Hexpm.Repo.Migrations.AddGravatarToEmails do
  use Ecto.Migration

  def up() do
    alter table(:emails) do
      add(:gravatar, :boolean, default: false, null: false)
    end

    execute("""
      UPDATE emails
      SET gravatar = true
      WHERE public
    """)
  end

  def down() do
    alter table(:emails) do
      remove(:gravatar)
    end
  end
end
