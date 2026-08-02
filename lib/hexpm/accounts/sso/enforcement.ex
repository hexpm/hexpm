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

  alias Hexpm.Accounts.{AuditLog, Key, Keys, Organization, OrganizationUser, User}
  alias Hexpm.Accounts.SSO.{Connection, Features, Identity, OrgSession}
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox
  alias Hexpm.OAuth.Token

  @type refusal :: :sso_required | :personal_key
  @type credential :: nil | Key.t() | Token.t()

  @default_session_lifetime 86_400
  @warning_window_seconds 14 * 24 * 60 * 60
  @notice_retention_seconds 30 * 24 * 60 * 60
  @pending_category "sso.enforcement_pending"
  @key_revoked_category "sso.key_revoked"
  @break_glass_category "sso.break_glass"
  @break_glass_notice_seconds 60 * 60

  @doc """
  The notices that are about one member rather than about their organization,
  and so go away with their account.
  """
  def member_notification_categories, do: [@pending_category, @key_revoked_category]

  @doc """
  The enforcement mode in force for an organization right now, or `:optional`
  when SSO cannot govern it at all.
  """
  @spec mode(Organization.t(), Connection.t() | nil) :: :optional | :pilot | :required
  def mode(organization, connection, now \\ DateTime.utc_now())

  def mode(%Organization{} = organization, %Connection{} = connection, now) do
    if Features.active?(organization) and Connection.enabled?(connection) do
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
  Whether this principal may reach this organization with this credential, and
  if not, why.

  `:sso_required` is a missing or expired organization access session, which
  authenticating through the provider fixes. `:personal_key` is a personal API
  key reaching an organization that does not accept one, which authenticating
  does not fix and a different credential does.

  One query, and none at all for someone who is not a member. `user_session_id`
  is the browser session in hand: an OAuth token carries its own instead, and a
  static credential carries none.
  """
  @spec check(Organization.t() | nil, term(), credential(), integer() | nil) ::
          :ok | {:error, refusal()}
  def check(organization, principal, credential \\ nil, user_session_id \\ nil)

  # The public repository belongs to no customer and is never governed. Saying
  # so here keeps the query off every public package page.
  def check(%Organization{id: 1}, _principal, _credential, _user_session_id), do: :ok

  def check(%Organization{}, %User{service: true}, _credential, _user_session_id), do: :ok

  def check(%Organization{} = organization, %User{} = user, credential, user_session_id) do
    if Features.available?() do
      user
      |> governed_memberships([organization.id])
      |> refuse(user, credential, user_session_id)
      |> Map.fetch(organization.id)
      |> case do
        {:ok, refusal} -> {:error, refusal}
        :error -> :ok
      end
    else
      :ok
    end
  end

  def check(_organization, _principal, _credential, _user_session_id), do: :ok

  @doc """
  Which of these organizations this credential currently reaches.

  The same decision `check/4` takes, over a set: a listing has no one resource
  to refuse for, so enforcement takes the organizations out of the list instead.
  """
  @spec reachable([Organization.t()], term(), credential(), integer() | nil) :: [Organization.t()]
  def reachable(organizations, principal, credential \\ nil, user_session_id \\ nil)

  def reachable(organizations, %User{service: true}, _credential, _user_session_id),
    do: organizations

  def reachable(organizations, %User{} = user, credential, user_session_id) do
    if Features.available?() do
      refused =
        user
        |> governed_memberships(Enum.map(organizations, & &1.id))
        |> refuse(user, credential, user_session_id)

      Enum.reject(organizations, &Map.has_key?(refused, &1.id))
    else
      organizations
    end
  end

  def reachable(organizations, _principal, _credential, _user_session_id), do: organizations

  @doc """
  Which of these organizations the member is governed by and has no current
  organization access session for on `user_session_id`.

  A removed member's organization is not in the answer, because they are not a
  member of it and nothing here would give it back. Only someone whose one
  missing piece is the authentication is named, which is what makes it safe to
  tell a client to go and get it.
  """
  @spec sso_required(term(), [String.t()], integer() | nil) :: [String.t()]
  def sso_required(principal, organization_names, user_session_id)

  def sso_required(_principal, [], _user_session_id), do: []

  def sso_required(%User{service: true}, _organization_names, _user_session_id), do: []

  def sso_required(%User{} = user, organization_names, user_session_id) do
    if Features.available?() do
      user
      |> governed_memberships({:names, organization_names})
      |> unauthenticated(user, user_session_id)
      |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization.name end)
    else
      []
    end
  end

  def sso_required(_principal, _organization_names, _user_session_id), do: []

  @doc """
  Which of these organizations enforcement governs this member's access to,
  whether or not they have authenticated for them yet.
  """
  @spec governed(term(), [String.t()]) :: [Organization.t()]
  def governed(principal, organization_names)

  def governed(_principal, []), do: []

  def governed(%User{service: true}, _organization_names), do: []

  def governed(%User{} = user, organization_names) do
    if Features.available?() do
      user
      |> governed_memberships({:names, organization_names})
      |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization end)
    else
      []
    end
  end

  def governed(_principal, _organization_names), do: []

  @doc """
  The organizations this user belongs to that turn personal API keys away.

  A key is a static credential with no session to check and nothing to expire
  it, so an organization requiring SSO chooses whether one may reach it at all.
  """
  @spec personal_key_refused(User.t() | Organization.t() | nil) :: [Organization.t()]
  def personal_key_refused(principal)

  def personal_key_refused(%User{service: true}), do: []

  def personal_key_refused(%User{} = user) do
    if Features.available?() do
      user
      |> governed_memberships(:all)
      |> Enum.filter(fn {_organization, connection, _member_enforcement} ->
        Connection.blocks_personal_keys?(connection)
      end)
      |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization end)
    else
      []
    end
  end

  def personal_key_refused(_principal), do: []

  @doc """
  What to tell someone refused for this organization, and what would fix it.
  """
  @spec refusal_message(refusal(), Organization.t()) :: String.t()
  def refusal_message(:sso_required, organization) do
    "organization #{organization.name} requires authenticating through its identity" <>
      " provider, sign in at #{login_url(organization)}"
  end

  def refusal_message(:personal_key, organization) do
    "organization #{organization.name} does not accept personal API keys, use an" <>
      " organization key for automation or run mix hex.user auth"
  end

  defp login_url(organization) do
    "#{HexpmWeb.Endpoint.url()}/sso/org/#{organization.name}"
  end

  defp governed_memberships(user, organization_ids) do
    from(
      member in OrganizationUser,
      join: organization in assoc(member, :organization),
      join: connection in Connection,
      on: connection.organization_id == member.organization_id,
      where: member.user_id == ^user.id,
      where: not is_nil(connection.enabled_at),
      select: {organization, connection, member.sso_enforcement}
    )
    |> restrict_organizations(organization_ids)
    |> Repo.all()
    |> Enum.filter(fn {organization, connection, member_enforcement} ->
      governed?(organization, connection, member_enforcement)
    end)
  end

  defp restrict_organizations(query, :all), do: query

  defp restrict_organizations(query, {:names, names}) do
    from(member in query,
      join: organization in assoc(member, :organization),
      where: organization.name in ^names
    )
  end

  defp restrict_organizations(query, organization_ids) do
    from(member in query, where: member.organization_id in ^organization_ids)
  end

  defp refuse([], _user, _credential, _user_session_id), do: %{}

  defp refuse(governed, user, credential, user_session_id) do
    if personal_key?(credential) do
      governed
      |> Enum.filter(fn {_organization, connection, _member_enforcement} ->
        Connection.blocks_personal_keys?(connection)
      end)
      |> refusals(:personal_key)
    else
      governed
      |> unauthenticated(user, session_id(credential, user_session_id))
      |> refusals(:sso_required)
    end
  end

  # The principal is a person, so a key in hand is one of theirs. An
  # organization's own key never reaches here.
  defp personal_key?(%Key{}), do: true
  defp personal_key?(_credential), do: false

  defp session_id(%Token{user_session_id: user_session_id}, _browser_session_id),
    do: user_session_id

  defp session_id(nil, browser_session_id), do: browser_session_id

  defp unauthenticated(governed, _user, nil), do: governed

  defp unauthenticated(governed, user, user_session_id) do
    organization_ids = Enum.map(governed, fn {organization, _, _} -> organization.id end)
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

    Enum.reject(governed, fn {organization, _, _} ->
      MapSet.member?(authenticated, organization.id)
    end)
  end

  defp refusals(governed, refusal) do
    Map.new(governed, fn {organization, _connection, _member_enforcement} ->
      {organization.id, refusal}
    end)
  end

  @doc """
  Mails members who will lose access when their organization starts requiring
  SSO and have not linked an identity yet.

  Only fires inside the window before the date, and a member is told once per
  organization rather than once per tick.
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
    |> Enum.filter(fn {_connection, organization} -> Features.active?(organization) end)
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
      select: {user, address.email}
    )
    |> Repo.all()
    |> Enum.map(fn {user, email} -> warn_member(connection, organization, user, email) end)
    |> Enum.count(&(&1 == :sent))
  end

  # The audit entry is the durable record, so the "once" hangs off it rather
  # than off the mail: the outbox row is deleted as soon as it is delivered,
  # and a member would be told again on every tick.
  defp warn_member(connection, organization, user, email) do
    if warned?(organization, user) do
      :skipped
    else
      %{user: user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
      |> AuditLog.build(
        "sso.enforcement.warned",
        {organization, user, connection.required_at}
      )
      |> Repo.insert!()

      Outbox.insert!(
        Outbox.prepare!(
          Emails.sso_enforcement_pending(
            organization.name,
            connection.required_at,
            HexpmWeb.Endpoint.url() <> "/sso/org/#{organization.name}",
            [email]
          ),
          category: @pending_category,
          group_key: "#{@pending_category}:#{organization.id}:#{user.id}",
          scope_key: "sso:user:#{user.id}",
          expires_at: DateTime.add(DateTime.utc_now(), @notice_retention_seconds, :second)
        )
      )

      :sent
    end
  end

  defp warned?(organization, user) do
    Repo.exists?(
      from(log in AuditLog,
        where: log.organization_id == ^organization.id,
        where: log.user_id == ^user.id,
        where: log.action == "sso.enforcement.warned"
      )
    )
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
      mode(organization, connection) == :required and Connection.blocks_personal_keys?(connection)
    end)
    |> Enum.map(fn {connection, organization} -> sweep_organization(organization, connection) end)
    |> Enum.sum()
  end

  defp sweep_organization(organization, connection) do
    stripped =
      organization
      |> blocked_personal_keys(connection)
      |> Enum.filter(&(strip_key(&1, organization) == :stripped))

    # One notice per owner rather than per key: a member with a key for each of
    # their projects should hear about it once.
    stripped
    |> Enum.group_by(& &1.user_id)
    |> Enum.each(fn {_user_id, keys} -> notify_key_owner(organization, keys) end)

    length(stripped)
  end

  @doc """
  The personal API keys this organization turns away, which are the ones its
  governed members hold.

  An exempt member is not governed, so their key reaches the organization on
  the same terms as before and nothing here takes it away.
  """
  @spec blocked_personal_keys(Organization.t(), Connection.t() | nil) :: [Key.t()]
  def blocked_personal_keys(organization, connection) do
    if Connection.blocks_personal_keys?(connection) do
      governed = governed_member_ids(organization, connection)

      organization
      |> Keys.personal_reaching_organization()
      |> Enum.filter(&MapSet.member?(governed, &1.user_id))
    else
      []
    end
  end

  defp governed_member_ids(organization, connection) do
    from(member in OrganizationUser,
      where: member.organization_id == ^organization.id,
      select: {member.user_id, member.sso_enforcement}
    )
    |> Repo.all()
    |> Enum.filter(fn {_user_id, member_enforcement} ->
      governed?(organization, connection, member_enforcement)
    end)
    |> MapSet.new(fn {user_id, _member_enforcement} -> user_id end)
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

        :stripped
    end
  end

  defp audit_key_revoke(key, organization, removed) do
    %{user: key.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
    |> Hexpm.Accounts.AuditLog.build("sso.key.revoke", {organization, key, removed})
    |> Repo.insert!()
  end

  defp notify_key_owner(organization, [%Key{user: user} | _] = keys) do
    recipients =
      from(address in Hexpm.Accounts.Email,
        where: address.user_id == ^user.id,
        where: address.primary and address.verified,
        select: address.email
      )
      |> Repo.all()

    if recipients != [] do
      enqueue_once(
        Emails.sso_key_revoked(organization.name, Enum.map(keys, & &1.name), recipients),
        category: @key_revoked_category,
        group_key: "#{@key_revoked_category}:#{organization.id}:#{user.id}",
        scope_key: "sso:user:#{user.id}"
      )
    end
  end

  @doc """
  Records that a governed member with no current organization access session
  reached one of the screens enforcement deliberately leaves open.

  Billing and the SSO configuration itself stay reachable so an organization
  whose provider has broken can fix it and keep paying. That is a residual
  bypass, so it is audited and the administrators are told, at most hourly per
  member so a few page loads are one notice.
  """
  @spec break_glass(Organization.t(), User.t(), atom(), map()) :: :ok
  def break_glass(%Organization{} = organization, %User{} = user, screen, audit_data) do
    unless recent_break_glass?(organization, user) do
      audit_data
      |> AuditLog.build("sso.break_glass", {organization, %{screen: to_string(screen)}})
      |> Repo.insert!()

      notify_admins_of_break_glass(organization, user)
    end

    :ok
  end

  # The audit entry is the durable record and is always written, so the window
  # hangs off it rather than off the mail, which an organization with no
  # confirmed administrator address never gets.
  defp recent_break_glass?(organization, user) do
    cutoff = DateTime.add(DateTime.utc_now(), -@break_glass_notice_seconds, :second)

    Repo.exists?(
      from(log in AuditLog,
        where: log.organization_id == ^organization.id,
        where: log.user_id == ^user.id,
        where: log.action == "sso.break_glass",
        where: log.inserted_at > ^cutoff
      )
    )
  end

  defp notify_admins_of_break_glass(organization, user) do
    recipients = admin_emails(organization)

    if recipients != [] do
      Outbox.insert!(
        Outbox.prepare!(
          Emails.sso_break_glass(organization.name, user.username, recipients),
          category: @break_glass_category,
          group_key: "#{@break_glass_category}:#{organization.id}:#{user.id}",
          scope_key: "sso:organization:#{organization.id}",
          expires_at: DateTime.add(DateTime.utc_now(), @notice_retention_seconds, :second)
        )
      )
    end
  end

  defp admin_emails(organization) do
    from(
      member in OrganizationUser,
      join: user in assoc(member, :user),
      join: address in assoc(user, :emails),
      where: member.organization_id == ^organization.id,
      where: member.role == "admin",
      where: address.primary and address.verified,
      select: address.email
    )
    |> Repo.all()
  end

  defp enqueue_once(email, opts) do
    group_key = Keyword.fetch!(opts, :group_key)

    if pending_entry?(group_key) do
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

  # An entry is deleted once it is delivered, so this only collapses a notice
  # that has not gone out yet.
  defp pending_entry?(group_key) do
    Repo.exists?(from(entry in Hexpm.Emails.OutboxEntry, where: entry.group_key == ^group_key))
  end
end
