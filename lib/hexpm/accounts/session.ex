defmodule Hexpm.Accounts.Session do
  use Hexpm.Schema
  alias Hexpm.Accounts.User

  schema "sessions" do
    belongs_to :user, User
    field :uuid, Ecto.UUID, autogenerate: true
    field :token_hash, :binary
    field :data, :map
    field :expires_at, :utc_datetime_usec
    field :active, :boolean

    timestamps()
  end

  def build(user, data, token) do
    expires_at = DateTime.add(DateTime.utc_now(), data.expires_in, :second)
    token_hash = :crypto.hash(:sha256, token)

    change(%Session{},
      user_id: user.id,
      active: true,
      expires_at: expires_at,
      data: data,
      token_hash: token_hash
    )
  end

  def get_active(uuid) do
    from(s in __MODULE__,
      join: u in User,
      on: u.id == s.user_id,
      where: [uuid: ^uuid, active: true],
      preload: [user: {u, [:emails, organizations: :repository]}]
    )
  end

  def update(session, data) do
    change(session, data: data)
  end

  def expire(%Session{} = session) do
    change(session, %{active: false, expires_at: DateTime.utc_now()})
  end

  def by_id(query \\ __MODULE__, id) do
    from(s in query, where: [id: ^id])
  end

  def by_user(query \\ __MODULE__, user) do
    from(s in query, where: fragment("(?->>'user_id')::integer", s.data) == ^user.id)
  end

  def all_inactive_by_user(user) do
    now = DateTime.utc_now()

    from(
      s in Session,
      where: s.user_id == ^user.id and (s.active == false or s.expires_at <= ^now)
    )
  end
end
