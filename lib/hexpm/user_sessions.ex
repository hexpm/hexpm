defmodule Hexpm.UserSessions do
  @moduledoc """
  Manages user sessions for both browser authentication and OAuth applications.

  ## Session Limits

  Users are limited to 5 active sessions (combined browser and OAuth) to balance
  security and usability. When this limit is reached, the least recently used
  session is automatically revoked. This prevents session buildup while allowing
  users to be logged in on multiple devices and use several OAuth applications.

  Organizations have a dynamic session limit of max(5, seat_count). For example,
  an organization with 4 seats gets 5 sessions (minimum), while an organization
  with 10 seats gets 10 sessions. This limit applies to API key sessions only,
  as organizations do not create browser or OAuth sessions.

  ## Session Expiration

  All sessions expire after 30 days of creation (non-sliding window). Sessions
  are automatically cleaned up by calling `cleanup_expired_sessions/0` periodically
  via a scheduled job (e.g., cron, Oban, Quantum).

  ## Last Use Tracking

  Browser sessions track last use via the login plug (throttled to once per 5 minutes).
  OAuth sessions track last use when tokens are issued or refreshed.
  """
  use Hexpm.Context

  import Hexpm.Accounts.AuditLog, only: [audit: 4]

  alias Hexpm.UserSession
  alias Hexpm.OAuth.Token

  @max_sessions 5
  @default_session_expires_in 30 * 24 * 60 * 60

  @doc """
  Calculates the session limit for an organization based on seat count.
  Returns max(5, seat_count), using cached billing_seats field.
  Returns minimum of 5 if not yet cached (will be updated by billing report).
  """
  def get_organization_session_limit(organization) do
    if is_integer(organization.billing_seats) and organization.billing_seats > 0 do
      max(@max_sessions, organization.billing_seats)
    else
      # Default to minimum if not cached yet (will be updated by billing report)
      @max_sessions
    end
  end

  @doc """
  Creates a browser session for a user.
  Enforces the session limit before creating.
  Requires audit data for security logging.
  """
  def create_browser_session(user, opts) do
    enforce_session_limit(user)

    session_token = :crypto.strong_rand_bytes(32)
    name = Keyword.get(opts, :name, "Browser Session")
    expires_at = DateTime.add(DateTime.utc_now(), @default_session_expires_in, :second)

    attrs = %{
      user_id: user.id,
      type: "browser",
      name: name,
      session_token: session_token,
      expires_at: expires_at
    }

    changeset = UserSession.changeset(%UserSession{}, attrs)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:session, changeset)
      |> audit(Keyword.fetch!(opts, :audit), "session.create", fn %{session: session} ->
        session
      end)

    case Repo.transaction(multi) do
      {:ok, %{session: session}} -> {:ok, session, session_token}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Creates an OAuth session for a user and client.
  Enforces the session limit before creating.
  Requires audit data for security logging.
  """
  def create_oauth_session(user, client_id, opts) do
    enforce_session_limit(user)

    expires_at = DateTime.add(DateTime.utc_now(), @default_session_expires_in, :second)

    attrs = %{
      user_id: user.id,
      type: "oauth",
      client_id: client_id,
      name: Keyword.get(opts, :name),
      expires_at: expires_at
    }

    changeset = UserSession.changeset(%UserSession{}, attrs)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:session, changeset)
      |> Ecto.Multi.run(:preload, fn _repo, %{session: session} ->
        {:ok, Repo.preload(session, :client)}
      end)
      |> audit(Keyword.fetch!(opts, :audit), "session.create", fn %{preload: session} ->
        session
      end)

    case Repo.transaction(multi) do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Creates an OAuth session for an API key (client credentials grant).

  Unlike regular OAuth sessions, API key sessions:
  - Expire with the access token (short-lived, typically 30 minutes)
  - Can be for users or organizations
  - Organizations have dynamic limits based on seat count: max(5, seat_count)
  Requires audit data for security logging.
  """
  def create_api_key_session(user, organization, client_id, expires_at, opts) do
    # Determine which user to use for session limit enforcement
    session_user = user || organization.user

    # Calculate session limit: use dynamic limit for orgs, default for users
    max_sessions =
      if organization do
        get_organization_session_limit(organization)
      else
        @max_sessions
      end

    # Pass max_sessions and key_id to enforce_session_limit
    enforce_session_limit(session_user,
      max_sessions: max_sessions,
      key_id: Keyword.get(opts, :key_id)
    )

    # Determine which user ID to use (user or org's user)
    user_id = if user, do: user.id, else: organization.user.id

    attrs = %{
      user_id: user_id,
      type: "oauth",
      client_id: client_id,
      name: Keyword.get(opts, :name),
      expires_at: expires_at,
      key_id: Keyword.get(opts, :key_id)
    }

    changeset = UserSession.changeset(%UserSession{}, attrs)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:session, changeset)
      |> Ecto.Multi.run(:preload, fn _repo, %{session: session} ->
        {:ok, Repo.preload(session, :client)}
      end)
      |> audit(Keyword.fetch!(opts, :audit), "session.create", fn %{preload: session} ->
        session
      end)

    case Repo.transaction(multi) do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Gets a browser session by token.
  """
  def get_browser_session_by_token(token) do
    now = DateTime.utc_now()

    from(s in UserSession,
      where:
        s.type == "browser" and s.session_token == ^token and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^now)
    )
    |> Repo.one()
  end

  @doc """
  Gets all active sessions for a user (both browser and OAuth).
  """
  def all_for_user(user) do
    now = DateTime.utc_now()

    from(s in UserSession,
      where:
        s.user_id == ^user.id and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^now),
      order_by: [desc: s.inserted_at],
      preload: [:client]
    )
    |> Repo.all()
  end

  @doc """
  Gets all active browser sessions for a user.
  """
  def all_browser_for_user(user) do
    from(s in UserSession,
      where: s.user_id == ^user.id and s.type == "browser" and is_nil(s.revoked_at),
      order_by: [desc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets all active OAuth sessions for a user.
  """
  def all_oauth_for_user(user) do
    from(s in UserSession,
      where: s.user_id == ^user.id and s.type == "oauth" and is_nil(s.revoked_at),
      order_by: [desc: s.inserted_at],
      preload: [:client]
    )
    |> Repo.all()
  end

  @doc """
  Revokes a session and all associated tokens (for OAuth sessions).
  """
  def revoke(session, revoke_at \\ nil, opts \\ [])

  def revoke(%UserSession{type: "oauth"} = session, revoke_at, opts) do
    revoke_at = revoke_at || DateTime.utc_now()

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:session, UserSession.changeset(session, %{revoked_at: revoke_at}))
      |> Ecto.Multi.update_all(
        :tokens,
        from(t in Token, where: t.user_session_id == ^session.id and is_nil(t.revoked_at)),
        set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
      )

    # Add audit if provided
    multi =
      if audit_data = Keyword.get(opts, :audit) do
        multi
        |> Ecto.Multi.run(:preload, fn _repo, %{session: revoked} ->
          {:ok, Repo.preload(revoked, :client)}
        end)
        |> audit(audit_data, "session.revoke", fn %{preload: s} -> s end)
      else
        multi
      end

    Repo.transaction(multi)
  end

  def revoke(%UserSession{type: "browser"} = session, revoke_at, opts) do
    revoke_at = revoke_at || DateTime.utc_now()

    changeset = UserSession.changeset(session, %{revoked_at: revoke_at})

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:session, changeset)

    # Add audit if provided
    multi =
      if audit_data = Keyword.get(opts, :audit) do
        audit(multi, audit_data, "session.revoke", fn %{session: s} -> s end)
      else
        multi
      end

    case Repo.transaction(multi) do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Revokes all sessions for a user (both browser and OAuth).
  Returns a query suitable for use in Multi.update_all.
  For OAuth sessions, associated tokens will also be revoked.
  """
  def revoke_all(user, revoke_at \\ nil) do
    revoke_at = revoke_at || DateTime.utc_now()

    # First, we need to revoke all OAuth tokens associated with this user's sessions
    # This is handled by updating the sessions table and separately updating tokens
    {from(s in UserSession,
       where: s.user_id == ^user.id and is_nil(s.revoked_at),
       update: [set: [revoked_at: ^revoke_at, updated_at: ^DateTime.utc_now()]]
     ),
     from(t in Token,
       where: t.user_id == ^user.id and is_nil(t.revoked_at),
       update: [set: [revoked_at: ^revoke_at, updated_at: ^DateTime.utc_now()]]
     )}
  end

  @doc """
  Updates the last use information for a session.
  """
  def update_last_use(%UserSession{} = session, usage_info) do
    session
    |> UserSession.update_last_use(usage_info)
    |> Repo.update()
  end

  @doc """
  Counts total active sessions for a user.
  """
  def count_for_user(user) do
    now = DateTime.utc_now()

    from(s in UserSession,
      where:
        s.user_id == ^user.id and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^now),
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Enforces the session limit by revoking least recently used sessions if needed.
  Called before creating a new session to ensure the user stays within the limit.
  Uses update_all for efficiency instead of fetching and iterating.

  ## Options
    * `:max_sessions` - Override the default limit (e.g., for organizations), defaults to 5
    * `:key_id` - When provided, preferentially revokes sessions from this API key first
  """
  def enforce_session_limit(user, opts \\ []) do
    max_sessions = Keyword.get(opts, :max_sessions, @max_sessions)
    count = count_for_user(user)

    if count >= max_sessions do
      now = DateTime.utc_now()
      revoke_count = count - max_sessions + 1
      key_id = Keyword.get(opts, :key_id)

      # Find the IDs of sessions to revoke
      session_ids_to_revoke = find_sessions_to_revoke(user, revoke_count, now, key_id)

      # Use a transaction to revoke sessions and their tokens atomically
      revoke_sessions_and_tokens(session_ids_to_revoke, now)
    end

    :ok
  end

  @doc """
  Revokes excess sessions for an organization when seat count is reduced.
  Called after reducing seats to ensure active sessions don't exceed the new limit.
  Uses the same LRU logic as enforce_session_limit.
  """
  def revoke_excess_sessions_for_organization(organization, new_seat_limit) do
    # Preload the organization user if not already loaded
    organization = Repo.preload(organization, :user)
    max_sessions = max(@max_sessions, new_seat_limit)

    count = count_for_user(organization.user)

    # Only revoke if we exceed the limit (no +1 since we're not creating a new session)
    if count > max_sessions do
      now = DateTime.utc_now()
      revoke_count = count - max_sessions

      # Find the IDs of sessions to revoke and revoke them
      session_ids_to_revoke = find_lru_sessions(organization.user, revoke_count, now)
      revoke_sessions_and_tokens(session_ids_to_revoke, now)
    end

    :ok
  end

  @doc """
  Cleans up expired sessions by deleting them from the database.

  This function should be called periodically (e.g., daily) via a scheduled job
  such as cron, Oban, or Quantum to prevent accumulation of expired records.

  Returns `{count, nil}` where count is the number of deleted sessions.
  """
  def cleanup_expired_sessions do
    now = DateTime.utc_now()

    from(s in UserSession,
      where: s.expires_at < ^now
    )
    |> Repo.delete_all()
  end

  defp find_sessions_to_revoke(user, revoke_count, now, key_id) do
    if key_id do
      # Try to revoke sessions from the same API key first
      key_session_ids = find_lru_sessions_for_key(user, revoke_count, now, key_id)

      # If we found enough sessions from this key, use only those
      # Otherwise, fall back to the general LRU approach
      if length(key_session_ids) >= revoke_count do
        key_session_ids
      else
        find_lru_sessions(user, revoke_count, now)
      end
    else
      # No key_id provided, use general LRU approach
      find_lru_sessions(user, revoke_count, now)
    end
  end

  defp find_lru_sessions(user, limit, now) do
    from(s in UserSession,
      where:
        s.user_id == ^user.id and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^now),
      order_by: [
        asc: fragment("(last_use->>'used_at')::timestamptz NULLS FIRST"),
        asc: s.inserted_at
      ],
      limit: ^limit,
      select: s.id
    )
    |> Repo.all()
  end

  defp find_lru_sessions_for_key(user, limit, now, key_id) do
    from(s in UserSession,
      where:
        s.user_id == ^user.id and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^now) and
          s.key_id == ^key_id,
      order_by: [
        asc: fragment("(last_use->>'used_at')::timestamptz NULLS FIRST"),
        asc: s.inserted_at
      ],
      limit: ^limit,
      select: s.id
    )
    |> Repo.all()
  end

  defp revoke_sessions_and_tokens(session_ids, now) do
    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :revoke_sessions,
      from(s in UserSession, where: s.id in ^session_ids),
      set: [revoked_at: now, updated_at: now]
    )
    |> Ecto.Multi.update_all(
      :revoke_tokens,
      from(t in Token,
        where: t.user_session_id in ^session_ids and is_nil(t.revoked_at)
      ),
      set: [revoked_at: now, updated_at: now]
    )
    |> Repo.transaction()
  end
end
