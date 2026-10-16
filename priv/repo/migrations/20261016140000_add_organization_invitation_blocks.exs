defmodule Hexpm.RepoBase.Migrations.AddOrganizationInvitationBlocks do
  use Ecto.Migration

  def up do
    alter table(:organization_invitations) do
      add :sent_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    execute "UPDATE organization_invitations SET sent_at = updated_at"

    create index(:organization_invitations, [:organization_id, :user_id, :sent_at])

    create table(:organization_invitation_blocks) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:organization_invitation_blocks, [:user_id, :organization_id])
    create index(:organization_invitation_blocks, [:organization_id])
  end

  def down do
    drop table(:organization_invitation_blocks)
    drop index(:organization_invitations, [:organization_id, :user_id, :sent_at])

    alter table(:organization_invitations) do
      remove :sent_at
    end
  end
end
