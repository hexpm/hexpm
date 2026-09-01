defmodule Hexpm.Accounts.SCIM.Resource do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  @moduledoc """
  The provider's handle on a person, decoupled from membership.

  The provider stores the `scim_id` it is given at create and addresses every
  later request to it, across deactivations and reactivations, so the row has
  to outlive the `organization_users` row it points at. There is no stored
  active flag: whether the person is a member, holds a pending invitation, or
  neither is derived on every read, so membership changed by hand in Hexpm is
  reflected on the provider's next request with no synchronization.
  """

  schema "organization_scim_resources" do
    field :scim_id, Ecto.UUID
    field :external_id, :string
    field :user_name, :string

    belongs_to :connection, Hexpm.Accounts.SSO.Connection
    belongs_to :organization, Organization
    belongs_to :user, User
    belongs_to :invitation, Hexpm.Accounts.OrganizationInvitation

    timestamps()
  end

  def build(connection) do
    %__MODULE__{
      connection_id: connection.id,
      organization_id: connection.organization_id,
      scim_id: Ecto.UUID.generate()
    }
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:external_id, :user_name, :user_id, :invitation_id])
    |> update_change(:user_name, &normalize_user_name/1)
    |> validate_required([:connection_id, :organization_id, :scim_id, :user_name])
    |> validate_length(:user_name, max: 320)
    |> validate_length(:external_id, max: 1_024)
    |> unique_constraint([:connection_id, :scim_id])
    |> unique_constraint([:connection_id, :user_name])
    |> unique_constraint([:connection_id, :user_id])
  end

  def normalize_user_name(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  def email_shaped?(value) when is_binary(value) do
    Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, value) and byte_size(value) <= 320
  end

  def email_shaped?(_value), do: false
end
