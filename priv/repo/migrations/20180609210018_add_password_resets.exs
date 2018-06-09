defmodule Hexpm.Repo.Migrations.AddPasswordResets do
  use Ecto.Migration

  def change do
    create table(:password_resets) do
      add(:key, :string, null: false)
      add(:user_id, references(:users))

      timestamps(updated_at: false)
    end

    create(index(:password_resets, [:user_id]))

    execute """
    INSERT INTO password_resets (key, user_id, inserted_at)
      SELECT reset_key, id, reset_expiry
        FROM users
        WHERE reset_key IS NOT NULL
    """

    alter table(:users) do
      remove(:reset_key)
      remove(:reset_expiry)
    end
  end
end
