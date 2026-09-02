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
  alias HexpmWeb.EmailView

  @type refusal :: :sso_required | :personal_key
  @type credential :: nil | Key.t() | Token.t()

  @default_session_lifetime 86_400
  @warning_window_seconds 14 * 24 * 60 * 60
  @pending_category "sso.enforcement_pending"
  @key_revoked_category "sso.key_revoked"
  @key_blocked_category "sso.key_blocked"
  @break_glass_category "sso.break_glass"
  @break_glass_notice_seconds 60 * 60

  @doc """
  The notices that are about one member rather than about their organization,
  and so go away with their account.
  """
  def member_notification_categories,
    do: [@pending_category, @key_revoked_category, @key_blocked_category]

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
  @spec governed?(Organization.t(), Connection.t() | nil, String.t() | nil, DateTime.t()) ::
          boolean()
  def governed?(organization, connection, member_enforcement, now \\ DateTime.utc_now()) do
    case mode(organization, connection, now) do
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

  Two queries at most: the memberships enforcement governs, and the organization
  access sessions when there is a session id in hand and something governed to
  check it against. Neither runs while the feature is off. `user_session_id` is
  the browser session in hand: an OAuth token carries its own instead, and a
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
    refused = refusals_for([organization.id], user, credential, user_session_id)

    case Map.fetch(refused, organization.id) do
      {:ok, refusal} -> {:error, refusal}
      :error -> :ok
    end
  end

  # An organization subject authenticates as the organization rather than as a
  # person and is never governed, and neither is an anonymous request, which
  # reaches nothing private to begin with.
  #
  # Written out rather than left as a catch-all: an unloaded association is a
  # bug on the caller's side, and a catch-all answers it with `:ok`, which is
  # the one answer that cannot be noticed.
  def check(%Organization{}, %Organization{}, _credential, _user_session_id), do: :ok
  def check(%Organization{}, nil, _credential, _user_session_id), do: :ok
  def check(nil, _principal, _credential, _user_session_id), do: :ok

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
    refused = refusals_for(Enum.map(organizations, & &1.id), user, credential, user_session_id)
    Enum.reject(organizations, &Map.has_key?(refused, &1.id))
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
    user
    |> governed_memberships({:names, organization_names})
    |> unauthenticated(user, user_session_id)
    |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization.name end)
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
    user
    |> governed_memberships({:names, organization_names})
    |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization end)
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
    user
    |> governed_memberships(:all)
    |> Enum.filter(fn {_organization, connection, _member_enforcement} ->
      Connection.blocks_personal_keys?(connection)
    end)
    |> Enum.map(fn {organization, _connection, _member_enforcement} -> organization end)
  end

  def personal_key_refused(_principal), do: []

  @doc """
  What to tell someone refused for this organization with the credential they
  used, and what would fix it.
  """
  @spec refusal_message(refusal(), Organization.t(), credential()) :: String.t()
  def refusal_message(refusal, organization, credential \\ nil)

  # Following a sign-in URL would not fix this token: the organization access it
  # produces lands on the browser session that visited it, not on the session
  # the token belongs to. The CLI asks for the session in hand instead, and only
  # for the organizations the project depends on, which a project that publishes
  # to this one but depends on none of its packages never asks for.
  #
  # No message names a client command: mix is not the only client, so each
  # client translates "authenticate again" into its own task.
  def refusal_message(:sso_required, organization, %Token{}) do
    "organization #{organization.name} requires authenticating through its identity" <>
      " provider, authenticate this session again from your Hex client"
  end

  def refusal_message(:sso_required, organization, _credential) do
    "organization #{organization.name} requires authenticating through its identity" <>
      " provider, which a username and password cannot do, sign in from your Hex" <>
      " client or use an organization key for automation"
  end

  def refusal_message(:personal_key, organization, _credential) do
    "organization #{organization.name} does not accept personal API keys, use an" <>
      " organization key for automation or sign in from your Hex client"
  end

  # Nothing is governed while the feature is off. Answering that here is what
  # keeps the query off every request that reaches enforcement at all.
  defp governed_memberships(user, organization_ids) do
    if Features.available?() do
      from(
        member in OrganizationUser,
        join: organization in assoc(member, :organization),
        as: :organization,
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
    else
      []
    end
  end

  defp restrict_organizations(query, :all), do: query

  defp restrict_organizations(query, {:names, names}) do
    from(member in query, where: as(:organization).name in ^names)
  end

  defp restrict_organizations(query, organization_ids) do
    from(member in query, where: member.organization_id in ^organization_ids)
  end

  # Which of these organizations this credential is refused for, and why, keyed
  # by organization id.
  defp refusals_for(organization_ids, user, credential, user_session_id) do
    user
    |> governed_memberships(organization_ids)
    |> refuse(user, credential, user_session_id)
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
  #
  # A token a personal key was exchanged for holds the key's standing: it is
  # minted with no refresh token and its session dies with it, so there is never
  # an organization access session for it to carry and judging it on one would
  # refuse it against a session that can never hold access.
  defp personal_key?(%Key{}), do: true

  defp personal_key?(%Token{grant_type: "client_credentials", user_id: user_id})
       when not is_nil(user_id),
       do: true

  defp personal_key?(_credential), do: false

  defp session_id(%Token{user_session_id: user_session_id}, _browser_session_id),
    do: user_session_id

  defp session_id(nil, browser_session_id), do: browser_session_id

  defp unauthenticated(governed, _user, nil), do: governed

  defp unauthenticated(governed, user, user_session_id) do
    organization_ids = Enum.map(governed, fn {organization, _, _} -> organization.id end)
    now = DateTime.utc_now()

    live =
      user_session_id
      |> OrgSession.live(now)
      |> OrgSession.for_user(user.id)

    authenticated =
      from(session in live,
        where: session.organization_id in ^organization_ids,
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
    from(member in members_with_identity(organization),
      join: user in assoc(member, :user),
      join: address in assoc(user, :emails),
      where: is_nil(member.sso_enforcement) or member.sso_enforcement == "enforced",
      where: is_nil(as(:identity).id),
      where: address.primary and address.verified,
      select: {user, address.email}
    )
    |> Repo.all()
    |> Enum.map(fn {user, email} -> warn_member(connection, organization, user, email) end)
    |> Enum.count(&(&1 == :sent))
  end

  # The audit entry is the durable record, so the "once" hangs off it rather
  # than off the mail: the outbox row is deleted as soon as it is delivered,
  # and a member would be told again on every tick. Both go in one transaction,
  # so a failure while building the mail does not leave the member recorded as
  # warned and never told.
  defp warn_member(connection, organization, user, email) do
    if warned?(organization, user) do
      :skipped
    else
      {:ok, _} =
        Repo.transaction(fn ->
          %{user: user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
          |> AuditLog.build(
            "sso.enforcement.warned",
            {organization, user, connection.required_at}
          )
          |> Repo.insert!()

          Outbox.enqueue!(
            Emails.sso_enforcement_pending(
              organization.name,
              connection.required_at,
              EmailView.email_url("/sso/org/#{organization.name}"),
              [email]
            ),
            category: @pending_category,
            group_key: "#{@pending_category}:#{organization.id}:#{user.id}",
            scope_key: "sso:user:#{user.id}"
          )
        end)

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
  wherever the organization requires SSO and chose to block them, and tells
  every member whose keys it turns away, whether or not anything was removed.

  Only the permissions naming the organization go. A key carrying every
  repository reaches other organizations too, so stripping it here would take
  unrelated access with it; those are refused at the request instead. A pilot
  refuses the keys of the members it pilots without removing anything, so those
  members are told and their keys are left as they are.

  Returns how many keys were changed.
  """
  @spec sweep_personal_keys() :: non_neg_integer()
  def sweep_personal_keys do
    from(connection in Connection,
      join: organization in assoc(connection, :organization),
      where: connection.personal_keys == "block",
      where: connection.enforcement_mode in ["pilot", "required"],
      where: not is_nil(connection.enabled_at),
      select: {connection, organization}
    )
    |> Repo.all()
    |> Enum.filter(fn {connection, organization} ->
      mode(organization, connection) != :optional
    end)
    |> Enum.map(fn {connection, organization} -> sweep_organization(organization, connection) end)
    |> Enum.sum()
  end

  # Stripping and telling the owner are one transaction. A stripped key no
  # longer matches `blocked_personal_keys/2`, so a crash between the two would
  # take the notice with it and the owner would never hear that the key they
  # publish with stopped reaching this organization.
  defp sweep_organization(organization, connection) do
    strip? = mode(organization, connection) == :required

    {:ok, outcomes} =
      Repo.transaction(fn ->
        outcomes =
          organization
          |> blocked_personal_keys(connection)
          |> Enum.map(fn key -> {key, key_outcome(key, organization, strip?)} end)

        # One notice per owner rather than per key: a member with a key for each
        # of their projects should hear about it once.
        outcomes
        |> Enum.group_by(fn {key, _outcome} -> key.user_id end)
        |> Enum.each(fn {_user_id, keys} -> notify_key_owner(organization, keys) end)

        outcomes
      end)

    Enum.count(outcomes, fn {_key, outcome} -> outcome in [:revoked, :trimmed] end)
  end

  # A pilot turns the key away without taking anything from it, and so does a
  # key whose only reach is every repository, which carries other organizations'
  # access along with this one's.
  defp key_outcome(_key, _organization, false = _strip?), do: :blocked

  defp key_outcome(key, organization, true = _strip?) do
    case strip_key(key, organization) do
      {:stripped, outcome} -> outcome
      :kept -> :blocked
    end
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
      governed = governed_member_ids(organization, connection, DateTime.utc_now())

      organization
      |> Keys.personal_reaching_organization()
      |> Enum.filter(&MapSet.member?(governed, &1.user_id))
    else
      []
    end
  end

  @doc """
  The personal API keys a future required-by date will turn away, and which the
  organization is not turning away yet.

  During a grace period the connection blocks personal keys but only governs the
  members already marked enforced, so the list an administrator reviews before
  the date would otherwise omit exactly the people the date is for.
  """
  @spec pending_personal_keys(Organization.t(), Connection.t() | nil) :: [Key.t()]
  def pending_personal_keys(%Organization{} = organization, %Connection{} = connection) do
    required_at = connection.required_at

    if Connection.blocks_personal_keys?(connection) and not is_nil(required_at) and
         DateTime.compare(DateTime.utc_now(), required_at) == :lt do
      now = governed_member_ids(organization, connection, DateTime.utc_now())
      later = governed_member_ids(organization, connection, required_at)
      pending = MapSet.difference(later, now)

      organization
      |> Keys.personal_reaching_organization()
      |> Enum.filter(&MapSet.member?(pending, &1.user_id))
    else
      []
    end
  end

  def pending_personal_keys(%Organization{}, nil), do: []

  defp governed_member_ids(organization, connection, now) do
    from(member in OrganizationUser,
      where: member.organization_id == ^organization.id,
      select: {member.user_id, member.sso_enforcement}
    )
    |> Repo.all()
    |> Enum.filter(fn {_user_id, member_enforcement} ->
      governed?(organization, connection, member_enforcement, now)
    end)
    |> MapSet.new(fn {user_id, _member_enforcement} -> user_id end)
  end

  defp strip_key(key, organization) do
    case Keys.organization_permissions(key, organization) do
      [] ->
        :kept

      removed ->
        remaining = key.permissions -- removed
        now = DateTime.utc_now()

        # A key with nothing left authenticates but authorizes nothing, and its
        # owner would get a 401 naming neither SSO nor this organization. Revoke
        # it instead of leaving an inert credential in their key list.
        fields =
          if remaining == [] do
            [permissions: remaining, revoke_at: now, updated_at: now]
          else
            [permissions: remaining, updated_at: now]
          end

        # The embed is declared `on_replace: :raise`, which is the right default
        # for a key's own edit form and in the way of removing entries here.
        Repo.update_all(from(row in Key, where: row.id == ^key.id), set: fields)

        audit_key_revoke(key, organization, removed)

        if remaining == [], do: {:stripped, :revoked}, else: {:stripped, :trimmed}
    end
  end

  defp audit_key_revoke(key, organization, removed) do
    %{user: key.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
    |> Hexpm.Accounts.AuditLog.build("sso.key.revoke", {organization, key, removed})
    |> Repo.insert!()
  end

  defp notify_key_owner(organization, [{%Key{user: user}, _outcome} | _] = keys) do
    recipients = user_emails(user)

    if recipients != [] do
      revoked = for {key, :revoked} <- keys, do: key.name
      trimmed = for {key, :trimmed} <- keys, do: key.name
      blocked = for {key, :blocked} <- keys, do: key

      if revoked != [] or trimmed != [] do
        enqueue_once(
          Emails.sso_key_revoked(organization.name, revoked, trimmed, recipients),
          category: @key_revoked_category,
          group_key: "#{@key_revoked_category}:#{organization.id}:#{user.id}",
          scope_key: "sso:user:#{user.id}"
        )
      end

      notify_blocked(organization, user, blocked, recipients)
    end
  end

  # A blocked key changes no state, so unlike the revoked notice this one has
  # nothing to make it stop: the outbox row is deleted on delivery, and the same
  # key is blocked again on the next tick. The audit entry is the durable record
  # the "once" hangs off, per key rather than per member, so minting another key
  # that this organization also refuses is announced instead of swallowed.
  defp notify_blocked(_organization, _user, [], _recipients), do: :skipped

  defp notify_blocked(organization, user, blocked, recipients) do
    announced = announced_blocked_key_ids(organization, user)

    case Enum.reject(blocked, &MapSet.member?(announced, &1.id)) do
      [] ->
        :skipped

      fresh ->
        Enum.each(fresh, &audit_key_blocked(organization, &1))

        Outbox.enqueue!(
          Emails.sso_key_blocked(organization.name, Enum.map(blocked, & &1.name), recipients),
          category: @key_blocked_category,
          group_key: "#{@key_blocked_category}:#{organization.id}:#{user.id}",
          scope_key: "sso:user:#{user.id}"
        )

        :sent
    end
  end

  defp announced_blocked_key_ids(organization, user) do
    from(log in AuditLog,
      where: log.organization_id == ^organization.id,
      where: log.user_id == ^user.id,
      where: log.action == "sso.key.blocked",
      select: log.params
    )
    |> Repo.all()
    |> MapSet.new(fn params -> get_in(params, ["key", "id"]) end)
  end

  defp audit_key_blocked(organization, key) do
    %{user: key.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
    |> AuditLog.build("sso.key.blocked", {organization, key})
    |> Repo.insert!()
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
    screen = to_string(screen)
    recent? = recent_break_glass?(organization, user, screen)

    audit_data
    |> AuditLog.build("sso.break_glass", {organization, %{screen: screen}})
    |> Repo.insert!()

    # Only the mail is rate limited. The audit entry is the one record that says
    # an action was taken without a session, so suppressing it would make a
    # sequence of repairs indistinguishable from an administrator who
    # authenticated normally.
    unless recent? do
      notify_admins_of_break_glass(organization, user, screen)
    end

    :ok
  end

  # Per screen rather than per member. The carve-out is thirteen actions
  # including deleting the connection, and the mail names one screen, so a
  # window covering all of them would announce whichever was reached first and
  # say nothing about the rest.
  #
  # The window hangs off the audit entry rather than off the mail, which an
  # organization with no confirmed administrator address never gets.
  defp recent_break_glass?(organization, user, screen) do
    cutoff = DateTime.add(DateTime.utc_now(), -@break_glass_notice_seconds, :second)

    Repo.exists?(
      from(log in AuditLog,
        where: log.organization_id == ^organization.id,
        where: log.user_id == ^user.id,
        where: log.action == "sso.break_glass",
        where: log.inserted_at > ^cutoff,
        where: fragment("?->>'screen'", log.params) == ^screen
      )
    )
  end

  defp notify_admins_of_break_glass(organization, user, screen) do
    recipients = admin_emails(organization)

    if recipients != [] do
      Outbox.enqueue!(
        Emails.sso_break_glass(organization.name, user.username, screen, recipients),
        category: @break_glass_category,
        group_key: "#{@break_glass_category}:#{organization.id}:#{user.id}:#{screen}",
        scope_key: "sso:organization:#{organization.id}"
      )
    end
  end

  # The members of an organization with their SSO identity attached where they
  # have one, so a query can select on not having one.
  @doc false
  def members_with_identity(organization) do
    from(member in OrganizationUser,
      left_join: identity in Identity,
      on:
        identity.organization_id == member.organization_id and
          identity.user_id == member.user_id,
      as: :identity,
      where: member.organization_id == ^organization.id
    )
  end

  # Where a notice about an organization goes.
  @doc false
  def admin_emails(organization) do
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

  # Where a notice about one account goes. The verified primary address only:
  # any address can be attached to an account unverified, so sending to all of
  # them would let an account holder mail an address they do not own.
  @doc false
  def user_emails(user) do
    from(address in Email,
      where: address.user_id == ^user.id,
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
      Outbox.enqueue!(email,
        category: Keyword.fetch!(opts, :category),
        group_key: group_key,
        scope_key: Keyword.fetch!(opts, :scope_key)
      )

      :sent
    end
  end

  # Collapses a notice that has not gone out yet; a delivered one stays on the
  # table as a record and must not stop the next.
  defp pending_entry?(group_key) do
    Repo.exists?(
      from(entry in Hexpm.Emails.OutboxEntry.undelivered(), where: entry.group_key == ^group_key)
    )
  end
end
