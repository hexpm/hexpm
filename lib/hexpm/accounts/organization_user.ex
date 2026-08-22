defmodule Hexpm.Accounts.OrganizationUser do
  use Hexpm.Schema

  @enforcements ~w(enforced exempt)

  schema "organization_users" do
    field :role, :string
    field :sso_enforcement, :string

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Sets whether SSO is enforced for this member regardless of the organization's
  mode. Nil follows the mode, "enforced" always does, "exempt" never does.
  """
  def enforcement_changeset(organization_user, attrs) do
    organization_user
    |> cast(attrs, [:sso_enforcement])
    |> update_change(:sso_enforcement, &nilify_blank/1)
    |> validate_inclusion(:sso_enforcement, @enforcements)
  end
end
