defmodule Hexpm.RepoBase.Migrations.IndexOrganizationInvitationsByAddressAndInviter do
  use Ecto.Migration

  def change do
    create index(:organization_invitations, [:email, :updated_at])
    create index(:organization_invitations, [:invited_by_user_id, :inserted_at])
  end
end
