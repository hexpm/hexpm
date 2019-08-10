defmodule Hexpm.Accounts.Session do
  use Hexpm.Schema

  schema "sessions" do
    field :token, :binary
    field :data, :map
    timestamps()
  end

  def build(data) do
    change(%Session{}, data: data, token: :crypto.strong_rand_bytes(96))
  end

  def update(session, data) do
    change(session, data: data)
  end

  def by_id(query \\ __MODULE__, id) do
    from(s in query, where: [id: ^id])
  end

  def by_user(query \\ __MODULE__, user) do
    from(s in query, where: fragment("(?->>'user_id')::integer", s.data) == ^user.id)
  end
end
