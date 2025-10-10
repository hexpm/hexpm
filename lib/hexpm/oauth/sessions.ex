defmodule Hexpm.OAuth.Sessions do
  use Hexpm.Context

  alias Hexpm.OAuth.{Session, Token}

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
  Gets all active OAuth sessions for a user.
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
  Updates the last use information for a session.
  """
  def update_last_use(%Session{} = session, usage_info) do
    session
    |> Session.update_last_use(usage_info)
    |> Repo.update()
  end
end
