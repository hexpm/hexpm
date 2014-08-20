defmodule HexWeb.API.Key do
  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  alias HexWeb.Util

  schema "keys" do
    belongs_to :user, HexWeb.User
    field :name, :string
    field :secret_first, :string
    field :secret_second, :string
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

        {first, second} = gen_key()
        key = %{key | name: name, secret_first: first, secret_second: second}
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

  def secret(key) do
    key.secret_first <> key.secret_second
  end

  def auth(<<first::binary-size(32), second::binary-size(32)>>) do
    # Database index lookup on the first part of the key and then
    # secure compare on the second part to avoid timing attacks

    user =
      from(k in HexWeb.API.Key,
           where: k.secret_first == ^first,
           join: u in k.user,
           select: assoc(u, keys: k))
      |> HexWeb.Repo.one

    if user && Util.secure_compare(List.first(user.keys.all).secret_second, second) do
      user
    end
  end

  defp gen_key do
    rand   = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    secret = Application.get_env(:hex_web, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, secret, rand) |> Base.encode16(case: :lower)

    {first, second}
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
  alias HexWeb.API.Key

  def render(key) do
    Key.__schema__(:keywords, key)
    |> Dict.take([:name, :created_at, :updated_at])
    |> Dict.update!(:created_at, &to_iso8601/1)
    |> Dict.update!(:updated_at, &to_iso8601/1)
    |> Dict.put(:url, api_url(["keys", key.name]))
    |> Dict.put(:secret, Key.secret(key))
    |> Enum.into(%{})
  end
end
