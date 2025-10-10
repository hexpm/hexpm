defmodule Hexpm.UserSessions do
  @moduledoc """
  Manages user sessions for both browser authentication and OAuth applications.

  ## Session Limits

  Users are limited to 5 active sessions (combined browser and OAuth) to balance
  security and usability. When this limit is reached, the least recently used
  session is automatically revoked. This prevents session buildup while allowing
  users to be logged in on multiple devices and use several OAuth applications.

  ## Session Expiration

  All sessions expire after 30 days of creation (non-sliding window). Sessions
  are automatically cleaned up by calling `cleanup_expired_sessions/0` periodically
  via a scheduled job (e.g., cron, Oban, Quantum).

  ## Last Use Tracking

  Browser sessions track last use via the login plug (throttled to once per 5 minutes).
  OAuth sessions track last use when tokens are issued or refreshed.
  """
  use Hexpm.Context

  alias Hexpm.UserSession
  alias Hexpm.OAuth.Token

  @max_sessions 5
  @default_session_expires_in 30 * 24 * 60 * 60

  @doc """
  Creates a browser session for a user.
  Enforces the session limit before creating.
  """
  def create_browser_session(user, opts \\ []) do
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

    case Repo.insert(changeset) do
      {:ok, session} -> {:ok, session, session_token}
      error -> error
    end
  end

  @doc """
  Creates an OAuth session for a user and client.
  Enforces the session limit before creating.
  """
  def create_oauth_session(user, client_id, opts \\ []) do
    enforce_session_limit(user)

    expires_at = DateTime.add(DateTime.utc_now(), @default_session_expires_in, :second)

    attrs = %{
      user_id: user.id,
      type: "oauth",
      client_id: client_id,
      name: Keyword.get(opts, :name),
      expires_at: expires_at
    }

    %UserSession{}
    |> UserSession.changeset(attrs)
    |> Repo.insert()
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
  def revoke(session, revoke_at \\ nil)

  def revoke(%UserSession{type: "oauth"} = session, revoke_at) do
    revoke_at = revoke_at || DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, UserSession.changeset(session, %{revoked_at: revoke_at}))
    |> Ecto.Multi.update_all(
      :tokens,
      from(t in Token, where: t.user_session_id == ^session.id and is_nil(t.revoked_at)),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  def revoke(%UserSession{type: "browser"} = session, revoke_at) do
    revoke_at = revoke_at || DateTime.utc_now()

    session
    |> UserSession.changeset(%{revoked_at: revoke_at})
    |> Repo.update()
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
  """
  def enforce_session_limit(user) do
    count = count_for_user(user)

    if count >= @max_sessions do
      now = DateTime.utc_now()
      revoke_count = count - @max_sessions + 1

      # Find the IDs of sessions to revoke using a subquery
      session_ids_to_revoke =
        from(s in UserSession,
          where:
            s.user_id == ^user.id and is_nil(s.revoked_at) and
              (is_nil(s.expires_at) or s.expires_at > ^now),
          order_by: [
            asc: fragment("(last_use->>'used_at')::timestamptz NULLS FIRST"),
            asc: s.inserted_at
          ],
          limit: ^revoke_count,
          select: s.id
        )

      # Use a transaction to revoke sessions and their tokens atomically
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :revoke_sessions,
        from(s in UserSession, where: s.id in subquery(session_ids_to_revoke)),
        set: [revoked_at: now, updated_at: now]
      )
      |> Ecto.Multi.update_all(
        :revoke_tokens,
        from(t in Token,
          where: t.user_session_id in subquery(session_ids_to_revoke) and is_nil(t.revoked_at)
        ),
        set: [revoked_at: now, updated_at: now]
      )
      |> Repo.transaction()
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
end
