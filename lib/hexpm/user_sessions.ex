defmodule Hexpm.UserSessions do
  use Hexpm.Context

  alias Hexpm.UserSession
  alias Hexpm.OAuth.Token

  @doc """
  Creates a browser session for a user.
  """
  def create_browser_session(user, opts \\ []) do
    session_token = :crypto.strong_rand_bytes(96)
    name = Keyword.get(opts, :name, "Browser Session")

    attrs = %{
      user_id: user.id,
      type: "browser",
      name: name,
      session_token: session_token
    }

    changeset = UserSession.changeset(%UserSession{}, attrs)

    case Repo.insert(changeset) do
      {:ok, session} -> {:ok, session, session_token}
      error -> error
    end
  end

  @doc """
  Creates an OAuth session for a user and client.
  """
  def create_oauth_session(user, client_id, opts \\ []) do
    attrs = %{
      user_id: user.id,
      type: "oauth",
      client_id: client_id,
      name: Keyword.get(opts, :name)
    }

    %UserSession{}
    |> UserSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a browser session by token.
  """
  def get_browser_session_by_token(token) do
    from(s in UserSession,
      where: s.type == "browser" and s.session_token == ^token and is_nil(s.revoked_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets all active sessions for a user (both browser and OAuth).
  """
  def all_for_user(user) do
    from(s in UserSession,
      where: s.user_id == ^user.id and is_nil(s.revoked_at),
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
    from(s in UserSession,
      where: s.user_id == ^user.id and is_nil(s.revoked_at),
      select: count(s.id)
    )
    |> Repo.one()
  end
end
