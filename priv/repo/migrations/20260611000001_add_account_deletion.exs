defmodule Hexpm.Repo.Migrations.AddAccountDeletion do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:reserved_usernames) do
      add :name, :string, null: false
      timestamps(updated_at: false)
    end

    create_if_not_exists(
      unique_index(:reserved_usernames, ["(lower(name))"], name: "reserved_usernames_name_idx")
    )

    create_if_not_exists table(:account_deletion_requests) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :primary_email, :string, null: false
      timestamps(updated_at: false)
    end

    create_if_not_exists(unique_index(:account_deletion_requests, [:user_id]))
  end
end
