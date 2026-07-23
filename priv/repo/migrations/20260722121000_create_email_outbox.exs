defmodule Hexpm.Repo.Migrations.CreateEmailOutbox do
  use Ecto.Migration

  def change do
    create table(:email_outbox_entries) do
      add :category, :text, null: false
      add :ordering_key, :text
      add :scope_key, :text
      add :email, :map, null: false
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:email_outbox_entries, [:ordering_key, :id])
    create index(:email_outbox_entries, [:scope_key])
    create index(:email_outbox_entries, [:expires_at])
  end
end
