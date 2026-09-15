defmodule Hexpm.Accounts.OrganizationTFANotification do
  use Hexpm.Schema

  schema "organization_tfa_notifications" do
    belongs_to :organization, Organization
    belongs_to :user, User
    field :revision, :integer
    field :stage, :string
    timestamps(updated_at: false)
  end
end
