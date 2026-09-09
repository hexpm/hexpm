defmodule Hexpm.RepoBase.Migrations.AddOrganizationTFA do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :tfa_required_at, :utc_datetime_usec
      add :tfa_session_lifetime_seconds, :integer, null: false, default: 604_800
      add :tfa_policy_revision, :integer, null: false, default: 0
    end

    create constraint(:organizations, :tfa_session_lifetime,
             check: "tfa_session_lifetime_seconds IN (86400, 604800, 2592000)"
           )

    alter table(:users) do
      add :tfa_generation, :integer, null: false, default: 0
    end

    alter table(:user_sessions) do
      add :tfa_verified_at, :utc_datetime_usec
      add :tfa_generation, :integer
      add :tfa_copied, :boolean, null: false, default: false
      add :tfa_source_session_id, references(:user_sessions, on_delete: :nilify_all)
    end
  end
end
