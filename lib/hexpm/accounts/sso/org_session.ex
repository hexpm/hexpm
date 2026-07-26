defmodule Hexpm.Accounts.SSO.OrgSession do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  @lifetime_seconds 24 * 60 * 60

  schema "organization_sso_sessions" do
    field :authenticated_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :user_session, Hexpm.UserSession
    belongs_to :identity, Hexpm.Accounts.SSO.Identity

    timestamps()
  end

  def lifetime_seconds, do: @lifetime_seconds

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :user_session_id,
      :identity_id,
      :authenticated_at,
      :expires_at,
      :revoked_at
    ])
    |> validate_required([
      :user_id,
      :organization_id,
      :user_session_id,
      :identity_id,
      :authenticated_at,
      :expires_at
    ])
    |> unique_constraint([:user_session_id, :organization_id])
  end
end
