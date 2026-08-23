defmodule Hexpm.Accounts.SSO.OrgSession do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

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

  @doc """
  The organization access a session is currently carrying: everything written
  against it that has neither been revoked nor lapsed, and only while the
  session it hangs off is itself live.

  The account session is part of the question rather than a check the callers
  each remember to add, so revoking or expiring a session takes the organization
  access with it whichever path did the revoking.
  """
  def live(user_session_id, now) do
    from(session in __MODULE__,
      join: user_session in assoc(session, :user_session),
      as: :user_session,
      where: session.user_session_id == ^user_session_id,
      where: is_nil(session.revoked_at) and session.expires_at > ^now,
      where: is_nil(user_session.revoked_at) and user_session.expires_at > ^now
    )
  end

  @doc """
  Narrows to the sessions the account owns.
  """
  def for_user(query, user_id) do
    from(session in query, where: session.user_id == ^user_id)
  end

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
