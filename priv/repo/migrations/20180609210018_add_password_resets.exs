defmodule Hexpm.Repo.Migrations.AddPasswordResets do
  use Ecto.Migration

  def change do
    create table(:password_resets) do
      add(:key, :string, null: false)
      add(:primary_email, :string, null: false)
      add(:user_id, references(:users))

      timestamps(updated_at: false)
    end

    create(index(:password_resets, [:user_id]))

    execute("""
    INSERT INTO password_resets (key, primary_email, user_id, inserted_at)
      SELECT users.reset_key, emails.email, users.id, users.reset_expiry
        FROM users
        JOIN emails ON users.id = emails.user_id
        WHERE users.reset_key IS NOT NULL AND emails.primary
    """)

    alter table(:users) do
      remove(:reset_key)
      remove(:reset_expiry)
    end
  end
end
