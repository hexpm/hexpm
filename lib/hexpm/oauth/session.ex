defmodule Hexpm.OAuth.Session do
  use Hexpm.Schema
  import Ecto.Query

  alias Hexpm.Accounts.User
  alias Hexpm.OAuth.{Client, Token}
  alias Hexpm.Repo

  schema "oauth_sessions" do
    field :name, :string
    field :revoked_at, :utc_datetime_usec

    embeds_one :last_use, Use, on_replace: :delete do
      field :used_at, :utc_datetime_usec
      field :user_agent, :string
      field :ip, :string
    end

    belongs_to :user, User
    belongs_to :client, Client, references: :client_id, type: :binary_id
    has_many :tokens, Token, foreign_key: :session_id

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:name, :revoked_at, :user_id, :client_id])
    |> validate_required([:user_id, :client_id])
    |> cast_embed(:last_use)
  end

  def build(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
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

    build(attrs)
  end

  @doc """
  Revokes the session and all associated tokens.
  """
  def revoke(%__MODULE__{} = session, revoke_at \\ nil) do
    revoke_at = revoke_at || DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, changeset(session, %{revoked_at: revoke_at}))
    |> Ecto.Multi.update_all(
      :tokens,
      from(t in Token, where: t.session_id == ^session.id and is_nil(t.revoked_at)),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  @doc """
  Checks if the session is revoked.
  """
  def revoked?(%__MODULE__{revoked_at: nil}), do: false

  def revoked?(%__MODULE__{revoked_at: revoked_at}) do
    DateTime.compare(DateTime.utc_now(), revoked_at) == :gt
  end

  @doc """
  Updates the last use information for the session.
  """
  def update_last_use(%__MODULE__{} = session, params) do
    if Repo.write_mode?() do
      session
      |> changeset(%{})
      |> put_embed(:last_use, struct(Use, params))
      |> Repo.update!()
    else
      session
    end
  end

  @doc """
  Lists all active sessions for a user.
  """
  def all_for_user(user) do
    from(s in __MODULE__,
      where: s.user_id == ^user.id and is_nil(s.revoked_at),
      order_by: [desc: s.inserted_at],
      preload: [:client]
    )
  end

  @doc """
  Gets a session by ID if it belongs to the user.
  """
  def get_for_user(user, session_id) do
    from(s in __MODULE__,
      where: s.id == ^session_id and s.user_id == ^user.id and is_nil(s.revoked_at),
      preload: [:client]
    )
  end

  @doc """
  Revokes all sessions for a user.
  """
  def revoke_all_for_user(user, revoke_at \\ nil) do
    revoke_at = revoke_at || DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :sessions,
      from(s in __MODULE__, where: s.user_id == ^user.id and is_nil(s.revoked_at)),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Ecto.Multi.update_all(
      :tokens,
      from(t in Token,
        join: s in __MODULE__,
        on: t.session_id == s.id,
        where: s.user_id == ^user.id and is_nil(t.revoked_at)
      ),
      set: [revoked_at: revoke_at, updated_at: DateTime.utc_now()]
    )
    |> Repo.transaction()
  end

  @doc """
  Cleans up expired sessions and their tokens.
  """
  def cleanup_expired do
    # Find sessions where all tokens have expired
    expired_session_ids =
      from(s in __MODULE__,
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
    from(s in __MODULE__, where: s.id in ^expired_session_ids) |> Repo.delete_all()
  end
end
