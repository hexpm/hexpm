defmodule Hexpm.RepoBase.Migrations.CreateOrganizationInvitations do
  use Ecto.Migration

  def change do
    create table(:organization_invitations) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      add :accepted_by_user_id, references(:users, on_delete: :nilify_all)
      add :email, :text, null: false
      add :role, :text, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_invitations, [:token_hash])

    create unique_index(:organization_invitations, [:organization_id, :email],
             where: "accepted_at IS NULL AND revoked_at IS NULL",
             name: :organization_invitations_pending_index
           )

    create index(:organization_invitations, [:expires_at])

    create constraint(:organization_invitations, :organization_invitation_role,
             check: "role IN ('admin', 'write', 'read')"
           )
  end
end
