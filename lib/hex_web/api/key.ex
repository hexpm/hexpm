defmodule HexWeb.API.Key do
  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  alias HexWeb.Util

  schema "keys" do
    belongs_to :user, HexWeb.User
    field :name, :string
    field :secret, :string
    field :created_at, :datetime
    field :updated_at, :datetime
  end

  validatep validate(key),
    name: present() and type(:string)

  def create(name, user) do
    now = Util.ecto_now
    key = struct(user.keys, name: name, created_at: now, updated_at: now)

    case validate(key) do
      [] ->
        names =
          from(k in HexWeb.API.Key, where: k.user_id == ^user.id, select: k.name)
          |> HexWeb.Repo.all
          |> Enum.into(HashSet.new)

        if Set.member?(names, name) do
          name = unique_name(name, names)
        end

        secret = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        key = %{key | name: name, secret: secret}
        {:ok, HexWeb.Repo.insert(key)}
      errors ->
        {:error, errors}
    end
  end

  def all(user) do
    from(k in HexWeb.API.Key, where: k.user_id == ^user.id)
    |> HexWeb.Repo.all
  end

  def get(name, user) do
    from(k in HexWeb.API.Key, where: k.user_id == ^user.id and k.name == ^name, limit: 1)
    |> HexWeb.Repo.one
  end

  def delete(key) do
    HexWeb.Repo.delete(key)
    :ok
  end

  def auth(secret) do
    from(k in HexWeb.API.Key,
         where: k.secret == ^secret,
         join: u in k.user,
         select: u)
    |> HexWeb.Repo.one
  end

  defp unique_name(name, names, counter \\ 2) do
    name_counter = "#{name}-#{counter}"
    if Set.member?(names, name_counter) do
      unique_name(name, names, counter + 1)
    else
      name_counter
    end
  end
end

defimpl HexWeb.Render, for: HexWeb.API.Key do
  import HexWeb.Util

  def render(key) do
    HexWeb.API.Key.__schema__(:keywords, key)
    |> Dict.take([:name, :secret, :created_at, :updated_at])
    |> Dict.update!(:created_at, &to_iso8601/1)
    |> Dict.update!(:updated_at, &to_iso8601/1)
    |> Dict.put(:url, api_url(["keys", key.name]))
    |> Enum.into(%{})
  end
end
