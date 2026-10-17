defmodule Hexpm.RepoBase.Migrations.AddUserToOrganizationInvitations do
  use Ecto.Migration

  def change do
    alter table(:organization_invitations) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :declined_at, :utc_datetime_usec
      modify :email, :text, null: true, from: {:text, null: false}
      modify :token_hash, :binary, null: true, from: {:binary, null: false}
    end

    create constraint(:organization_invitations, :organization_invitation_recipient,
             check:
               "(user_id IS NULL AND email IS NOT NULL AND token_hash IS NOT NULL) OR " <>
                 "(user_id IS NOT NULL AND email IS NULL AND token_hash IS NULL)"
           )

    create unique_index(:organization_invitations, [:organization_id, :user_id],
             where: "accepted_at IS NULL AND revoked_at IS NULL",
             name: :organization_invitations_pending_user_index
           )

    create index(:organization_invitations, [:user_id, :updated_at])
  end
end
