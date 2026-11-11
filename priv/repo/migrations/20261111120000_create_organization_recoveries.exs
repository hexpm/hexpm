defmodule Hexpm.Repo.Migrations.CreateOrganizationRecoveries do
  use Ecto.Migration

  def change do
    create table(:organization_recoveries) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :old_admin_id, references(:users, on_delete: :nilify_all)
      add :started_by_user_id, references(:users, on_delete: :nilify_all)
      add :billing_email, :text, null: false
      add :card_brand, :text
      add :card_last4, :text
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :verified_at, :utc_datetime_usec
      add :completes_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :canceled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_recoveries, [:token_hash])

    create unique_index(:organization_recoveries, [:organization_id],
             where: "completed_at IS NULL AND canceled_at IS NULL",
             name: :organization_recoveries_open_index
           )

    create index(:organization_recoveries, [:completes_at],
             where: "completed_at IS NULL AND canceled_at IS NULL"
           )
  end
end
