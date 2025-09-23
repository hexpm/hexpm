defmodule Hexpm.OAuth.Sessions do
  use Hexpm.Context

  alias Hexpm.OAuth.{Session, Token}

  @doc """
  Gets a session by ID.
  """
  def get(id) do
    Repo.get(Session, id)
  end

  @doc """
  Gets a session by ID if it belongs to the user.
  """
  def get_for_user(user, session_id) do
    from(s in Session,
      where: s.id == ^session_id and s.user_id == ^user.id and is_nil(s.revoked_at),
      preload: [:client]
    )
    |> Repo.one()
  end

  @doc """
  Lists all active sessions for a user.
  """
  def all_for_user(user) do
    from(s in Session,
      where: s.user_id == ^user.id and is_nil(s.revoked_at),
      order_by: [desc: s.inserted_at],
      preload: [:client]
    )
    |> Repo.all()
  end

  @doc """
  Creates a new OAuth session for a user and client.
  """
  def create_for_user(user, client_id, opts \\ []) do
    attrs = %{
      user_id: user.id,
      client_id: client_id,
      name: Keyword.get(opts, :name)
    }

    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Revokes the session and all associated tokens.
  """
  def revoke(%Session{} = session, revoke_at \\ nil) do
    revoke_at = revoke_at || DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, Session.changeset(session, %{revoked_at: revoke_at}))
    |> Ecto.Multi.update_all(
      :tokens,
      from(t in Token, where: t.session_id == ^session.id and is_nil(t.revoked_at)),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  @doc """
  Revokes all sessions for a user.
  """
  def revoke_all_for_user(user, revoke_at \\ nil) do
    revoke_at = revoke_at || DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :sessions,
      from(s in Session, where: s.user_id == ^user.id and is_nil(s.revoked_at)),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Ecto.Multi.update_all(
      :tokens,
      from(t in Token,
        join: s in Session,
        on: t.session_id == s.id,
        where: s.user_id == ^user.id and is_nil(t.revoked_at)
      ),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  @doc """
  Checks if the session is revoked.
  """
  def revoked?(%Session{revoked_at: nil}), do: false

  def revoked?(%Session{revoked_at: revoked_at}) do
    DateTime.compare(DateTime.utc_now(), revoked_at) == :gt
  end

  @doc """
  Updates the last use information for the session.
  """
  def update_last_use(%Session{} = session, params) do
    if Repo.write_mode?() do
      session
      |> Session.changeset(%{})
      |> put_embed(:last_use, struct(Session.Use, params))
      |> Repo.update!()
    else
      session
    end
  end

  @doc """
  Cleans up expired sessions and their tokens.
  """
  def cleanup_expired do
    # Find sessions where all tokens have expired
    expired_session_ids =
      from(s in Session,
        left_join: t in Token,
        on: t.session_id == s.id and t.expires_at > ^DateTime.utc_now(),
        where: is_nil(s.revoked_at),
        group_by: s.id,
        having: count(t.id) == 0,
        select: s.id
      )
      |> Repo.all()

    # Delete expired sessions and their tokens
    from(t in Token, where: t.session_id in ^expired_session_ids) |> Repo.delete_all()
    from(s in Session, where: s.id in ^expired_session_ids) |> Repo.delete_all()
  end
end
