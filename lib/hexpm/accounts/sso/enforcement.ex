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

  alias Hexpm.Accounts.{Key, Keys, Organization, OrganizationUser, User}
  alias Hexpm.Accounts.SSO.{Connection, Features, Identity, OrgSession}
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox

  @default_session_lifetime 86_400
  @warning_window_seconds 14 * 24 * 60 * 60
  @notice_retention_seconds 30 * 24 * 60 * 60
  @pending_category "sso.enforcement_pending"
  @key_revoked_category "sso.key_revoked"

  def notification_categories, do: [@pending_category, @key_revoked_category]

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

  @doc """
  Mails members who will lose access when their organization starts requiring
  SSO and have not linked an identity yet.

  Only fires inside the window before the date, and the outbox group key means a
  member is told once per organization rather than once per tick.
  """
  @spec warn_pending() :: non_neg_integer()
  def warn_pending do
    now = DateTime.utc_now()
    horizon = DateTime.add(now, @warning_window_seconds, :second)

    from(connection in Connection,
      join: organization in assoc(connection, :organization),
      where: connection.enforcement_mode == "required",
      where: not is_nil(connection.enabled_at),
      where: connection.required_at > ^now and connection.required_at <= ^horizon,
      select: {connection, organization}
    )
    |> Repo.all()
    |> Enum.filter(fn {_connection, organization} -> Features.enabled?(organization) end)
    |> Enum.map(fn {connection, organization} -> warn_organization(connection, organization) end)
    |> Enum.sum()
  end

  defp warn_organization(connection, organization) do
    from(
      member in OrganizationUser,
      join: user in assoc(member, :user),
      join: address in assoc(user, :emails),
      left_join: identity in Identity,
      on:
        identity.organization_id == member.organization_id and identity.user_id == member.user_id,
      where: member.organization_id == ^organization.id,
      where: is_nil(member.sso_enforcement) or member.sso_enforcement == "enforced",
      where: is_nil(identity.id),
      where: address.primary and address.verified,
      select: {member.user_id, address.email}
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, email} ->
      enqueue_once(
        Emails.sso_enforcement_pending(
          organization.name,
          connection.required_at,
          HexpmWeb.Endpoint.url() <> "/sso/org/#{organization.name}",
          [email]
        ),
        category: @pending_category,
        group_key: "#{@pending_category}:#{organization.id}:#{user_id}",
        scope_key: "sso:organization:#{organization.id}"
      )
    end)
    |> Enum.count(&(&1 == :sent))
  end

  @doc """
  Removes this organization's permissions from its members' personal API keys,
  wherever the organization requires SSO and chose to block them.

  Only the permissions naming the organization go. A key carrying every
  repository reaches other organizations too, so stripping it here would take
  unrelated access with it; those are refused at the request instead.
  """
  @spec sweep_personal_keys() :: non_neg_integer()
  def sweep_personal_keys do
    from(connection in Connection,
      join: organization in assoc(connection, :organization),
      where: connection.personal_keys == "block",
      where: connection.enforcement_mode == "required",
      where: not is_nil(connection.enabled_at),
      select: {connection, organization}
    )
    |> Repo.all()
    |> Enum.filter(fn {connection, organization} ->
      Features.enabled?(organization) and Connection.blocks_personal_keys?(connection)
    end)
    |> Enum.map(fn {_connection, organization} -> sweep_organization(organization) end)
    |> Enum.sum()
  end

  defp sweep_organization(organization) do
    organization
    |> Keys.personal_reaching_organization()
    |> Enum.map(&strip_key(&1, organization))
    |> Enum.count(&(&1 == :stripped))
  end

  defp strip_key(key, organization) do
    case Keys.organization_permissions(key, organization) do
      [] ->
        :kept

      removed ->
        # The embed is declared `on_replace: :raise`, which is the right default
        # for a key's own edit form and in the way of removing entries here.
        Repo.update_all(
          from(row in Key, where: row.id == ^key.id),
          set: [permissions: key.permissions -- removed, updated_at: DateTime.utc_now()]
        )

        audit_key_revoke(key, organization, removed)
        notify_key_owner(key, organization)

        :stripped
    end
  end

  defp audit_key_revoke(key, organization, removed) do
    %{user: key.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
    |> Hexpm.Accounts.AuditLog.build("sso.key.revoke", {organization, key, removed})
    |> Repo.insert!()
  end

  defp notify_key_owner(%Key{user: user} = key, organization) do
    recipients =
      from(address in Hexpm.Accounts.Email,
        where: address.user_id == ^user.id,
        where: address.primary and address.verified,
        select: address.email
      )
      |> Repo.all()

    if recipients != [] do
      enqueue_once(
        Emails.sso_key_revoked(organization.name, key.name, recipients),
        category: @key_revoked_category,
        group_key: "#{@key_revoked_category}:#{organization.id}:#{key.id}",
        scope_key: "sso:organization:#{organization.id}"
      )
    end
  end

  defp enqueue_once(email, opts) do
    group_key = Keyword.fetch!(opts, :group_key)

    if Repo.exists?(from(entry in Hexpm.Emails.OutboxEntry, where: entry.group_key == ^group_key)) do
      :skipped
    else
      Outbox.insert!(
        Outbox.prepare!(email,
          category: Keyword.fetch!(opts, :category),
          group_key: group_key,
          scope_key: Keyword.fetch!(opts, :scope_key),
          expires_at: DateTime.add(DateTime.utc_now(), @notice_retention_seconds, :second)
        )
      )

      :sent
    end
  end
end
