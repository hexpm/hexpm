defmodule Hexpm.Accounts.OrganizationUser do
  use Hexpm.Schema

  @enforcements ~w(enforced exempt)

  schema "organization_users" do
    field :role, :string
    field :sso_enforcement, :string
    field :public, :boolean, default: false

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Sets whether the membership is listed on the user's and organization's public profiles.
  Only the member changes it, and it starts hidden.
  """
  def visibility_changeset(organization_user, attrs) do
    organization_user
    |> cast(attrs, [:public])
    |> validate_required([:public])
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
