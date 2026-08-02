defmodule Hexpm.Accounts.SSO.Enforcement do
  @moduledoc """
  Whether a member has to have authenticated against their organization's
  identity provider to reach it, and which organizations they are currently
  locked out of for not having.

  Enforcement is per organization and evaluated against the resource, never a
  switch on the account. It only ever applies to human credentials: an
  organization-owned key authenticates as the organization rather than as a
  person and is never governed.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.{Organization, OrganizationUser, User}
  alias Hexpm.Accounts.SSO.{Connection, Features, OrgSession}

  @default_session_lifetime 86_400

  @doc """
  The enforcement mode in force for an organization right now, or `:optional`
  when SSO cannot govern it at all.
  """
  @spec mode(Organization.t(), Connection.t() | nil) :: :optional | :pilot | :required
  def mode(organization, connection, now \\ DateTime.utc_now())

  def mode(%Organization{} = organization, %Connection{} = connection, now) do
    if Features.enabled?(organization) and Connection.enabled?(connection) do
      connection |> Connection.enforcement_mode(now) |> String.to_existing_atom()
    else
      :optional
    end
  end

  def mode(%Organization{}, nil, _now), do: :optional

  @doc """
  Whether this member's access to this organization is subject to enforcement.
  """
  @spec governed?(Organization.t(), Connection.t() | nil, String.t() | nil) :: boolean()
  def governed?(organization, connection, member_enforcement) do
    case mode(organization, connection) do
      :optional -> false
      :pilot -> member_enforcement == "enforced"
      :required -> member_enforcement != "exempt"
    end
  end

  @doc """
  How long an organization access session lasts. One number for every path,
  browser and OAuth session alike, so the setting means what it says.
  """
  @spec session_lifetime(Connection.t() | nil) :: pos_integer()
  def session_lifetime(%Connection{session_lifetime_seconds: seconds})
      when is_integer(seconds) and seconds > 0,
      do: seconds

  def session_lifetime(_connection), do: @default_session_lifetime

  @doc """
  The organizations this user is a member of, is governed by, and has no current
  organization access session for on `user_session_id`.

  One query, and none at all for a user with no organization memberships, which
  is almost everyone. Pass `nil` for the session to treat every governed
  organization as blocked, which is what a credential that cannot hold a session
  needs.
  """
  @spec blocked_organization_ids(User.t() | nil, integer() | nil) :: MapSet.t()
  def blocked_organization_ids(user, user_session_id)

  def blocked_organization_ids(nil, _user_session_id), do: MapSet.new()

  def blocked_organization_ids(%User{} = user, user_session_id) do
    if Features.available?() do
      user |> governed_organizations() |> reject_authenticated(user, user_session_id)
    else
      MapSet.new()
    end
  end

  defp governed_organizations(user) do
    from(
      member in OrganizationUser,
      join: organization in assoc(member, :organization),
      join: connection in Connection,
      on: connection.organization_id == member.organization_id,
      where: member.user_id == ^user.id,
      where: not is_nil(connection.enabled_at),
      select: {organization, connection, member.sso_enforcement}
    )
    |> Repo.all()
    |> Enum.filter(fn {organization, connection, member_enforcement} ->
      governed?(organization, connection, member_enforcement)
    end)
    |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization.id end)
  end

  defp reject_authenticated([], _user, _user_session_id), do: MapSet.new()

  defp reject_authenticated(organization_ids, _user, nil), do: MapSet.new(organization_ids)

  defp reject_authenticated(organization_ids, user, user_session_id) do
    now = DateTime.utc_now()

    authenticated =
      from(
        session in OrgSession,
        where: session.user_session_id == ^user_session_id,
        where: session.user_id == ^user.id,
        where: session.organization_id in ^organization_ids,
        where: is_nil(session.revoked_at) and session.expires_at > ^now,
        select: session.organization_id
      )
      |> Repo.all()
      |> MapSet.new()

    organization_ids |> MapSet.new() |> MapSet.difference(authenticated)
  end
end
