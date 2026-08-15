defmodule Hexpm.Accounts.OrganizationInvitation do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  @lifetime_seconds 7 * 24 * 60 * 60
  @roles ~w(admin write read)

  schema "organization_invitations" do
    field :email, :string
    field :role, :string
    field :token_hash, :binary, redact: true
    field :raw_token, :string, virtual: true, redact: true
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :invited_by_user, User
    belongs_to :accepted_by_user, User

    timestamps()
  end

  def lifetime_seconds, do: @lifetime_seconds

  def roles, do: @roles

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :organization_id,
      :invited_by_user_id,
      :email,
      :role,
      :token_hash,
      :expires_at
    ])
    |> validate_required([:organization_id, :email, :role, :token_hash, :expires_at])
    |> update_change(:email, &normalize_email/1)
    |> validate_length(:email, max: 320)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "is not a valid email")
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:token_hash)
    |> unique_constraint(:email,
      name: :organization_invitations_pending_index,
      message: "has already been invited"
    )
  end

  def reissue_changeset(invitation, token_hash, expires_at) do
    invitation
    |> cast(%{"role" => invitation.role}, [:role])
    |> put_change(:token_hash, token_hash)
    |> put_change(:expires_at, expires_at)
    |> validate_inclusion(:role, @roles)
  end

  def accept_changeset(invitation, user, now) do
    change(invitation, accepted_at: now, accepted_by_user_id: user.id)
  end

  def revoke_changeset(invitation, now) do
    change(invitation, revoked_at: now)
  end

  def normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  def pending?(%__MODULE__{} = invitation, now) do
    is_nil(invitation.accepted_at) and is_nil(invitation.revoked_at) and
      DateTime.compare(invitation.expires_at, now) == :gt
  end
end
