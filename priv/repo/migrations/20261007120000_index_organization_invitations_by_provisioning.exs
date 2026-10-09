defmodule Hexpm.RepoBase.Migrations.IndexOrganizationInvitationsByProvisioning do
  use Ecto.Migration

  def change do
    create index(:organization_invitations, [:organization_id, :updated_at],
             where: "invited_by_user_id IS NULL"
           )
  end
end
