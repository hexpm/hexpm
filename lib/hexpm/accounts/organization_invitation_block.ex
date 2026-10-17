defmodule Hexpm.Accounts.OrganizationInvitationBlock do
  use Hexpm.Schema

  schema "organization_invitation_blocks" do
    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps(updated_at: false)
  end
end
