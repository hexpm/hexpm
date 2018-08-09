defmodule Hexpm.Repo.Migrations.AddServiceToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add(:service, :boolean, default: false)
    end

    execute("ALTER TABLE users ALTER password DROP NOT NULL")

    execute("""
    INSERT INTO users (username, service, inserted_at, updated_at)
    VALUES ('hexdocs', true, now(), now())
    """)
  end

  def down do
    execute("DELETE FROM users WHERE username = 'hexdocs'")

    execute("ALTER TABLE users ALTER password SET NOT NULL")

    alter table(:users) do
      remove(:service)
    end
  end
end
