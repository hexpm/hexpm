defmodule Hexpm.RepoBase.Migrations.AddOrganizationTFANotifications do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :tfa_policy_updated_at, :utc_datetime_usec
    end

    create table(:organization_tfa_notifications) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :revision, :integer, null: false
      add :stage, :string, null: false
      timestamps(updated_at: false)
    end

    create unique_index(
             :organization_tfa_notifications,
             [:organization_id, :revision, :user_id, :stage],
             name: :organization_tfa_notifications_dedup
           )
  end
end
