defmodule Hexpm.RepoBase.Migrations.CreateOrganizationDomains do
  use Ecto.Migration

  def change do
    create table(:organization_domains) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :added_by_user_id, references(:users, on_delete: :nilify_all)
      add :domain, :text, null: false
      add :verification_token, :text, null: false
      add :verified_at, :utc_datetime_usec
      add :last_checked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_domains, [:organization_id, :domain])
    create index(:organization_domains, [:verified_at])
  end
end
