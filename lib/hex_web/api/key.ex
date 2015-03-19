defmodule HexWeb.API.Key do
  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias HexWeb.Util

  schema "keys" do
    belongs_to :user, HexWeb.User
    field :name, :string
    field :secret_first, :string
    field :secret_second, :string
    field :created_at, :datetime
    field :updated_at, :datetime

    # Only used after key creation to hold the users key (not hashed)
    # the user key will never be retrievable after this
    field :user_secret, :string, virtual: true
  end

  validatep validate(key),
    # name: present() and type(:string)
    name: present()

  def create(name, user) do
    now = Util.ecto_now
    key = struct(user.keys, name: name, created_at: now, updated_at: now)

    if errors = validate(key) do
      {:error, errors}
    else
      names =
        from(k in HexWeb.API.Key, where: k.user_id == ^user.id, select: k.name)
        |> HexWeb.Repo.all
        |> Enum.into(HashSet.new)

      if Set.member?(names, name) do
        name = unique_name(name, names)
      end

      {user_secret, first, second} = gen_key()
      key = %{key | name: name,
                    user_secret: user_secret,
                    secret_first: first,
                    secret_second: second}
      {:ok, HexWeb.Repo.insert(key)}
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

  def auth(user_secret) do
    # Database index lookup on the first part of the key and then
    # secure compare on the second part to avoid timing attacks
    app_secret = Application.get_env(:hex_web, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

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
    user_secret = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    app_secret  = Application.get_env(:hex_web, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    {user_secret, first, second}
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
    entity =
      Key.__schema__(:keywords, key)
      |> Dict.take([:name, :created_at, :updated_at])
      |> Dict.update!(:created_at, &to_iso8601/1)
      |> Dict.update!(:updated_at, &to_iso8601/1)
      |> Dict.put(:url, api_url(["keys", key.name]))
      |> Enum.into(%{})

    if secret = key.user_secret do
      Map.put(entity, :secret, secret)
    else
      entity
    end
  end
end
