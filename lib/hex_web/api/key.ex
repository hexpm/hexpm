defmodule HexWeb.API.Key do
  use Ecto.Model

  @timestamps_opts [usec: true]

  schema "keys" do
    field :name, :string
    field :secret_first, :string
    field :secret_second, :string
    timestamps

    belongs_to :user, HexWeb.User

    # Only used after key creation to hold the users key (not hashed)
    # the user key will never be retrievable after this
    field :user_secret, :string, virtual: true
  end

  before_insert :unique_name

  defp changeset(key, params) do
    cast(key, params, ~w(name), [])
  end

  def create(user, params) do
    {user_secret, first, second} = gen_key()

    changeset =
      build(user, :keys)
      |> changeset(params)
      |> put_change(:user_secret, user_secret)
      |> put_change(:secret_first, first)
      |> put_change(:secret_second, second)

    if changeset.valid? do
      {:ok, HexWeb.Repo.insert(changeset)}
    else
      {:error, changeset.errors}
    end
  end

  def all(user) do
    assoc(user, :keys)
    |> HexWeb.Repo.all
  end

  def get(name, user) do
    from(k in assoc(user, :keys), where: k.name == ^name, limit: 1)
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

    result =
      from(k in HexWeb.API.Key,
           where: k.secret_first == ^first,
           join: u in assoc(k, :user),
           select: {u, k})
      |> HexWeb.Repo.one

    case result do
      {user, key} ->
        if Comeonin.Tools.secure_check(key.secret_second, second) do
          user
        end
      nil ->
        nil
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

  defp unique_name(changeset) do
    {:ok, name} = fetch_change(changeset, :name)

    names =
      from(u in assoc(changeset.model, :user),
           join: k in assoc(u, :keys),
           select: k.name)
      |> HexWeb.Repo.all
      |> Enum.into(HashSet.new)

    if Set.member?(names, name) do
      name = find_unique_name(name, names)
    end

    put_change(changeset, :name, name)
  end

  defp find_unique_name(name, names, counter \\ 2) do
    name_counter = "#{name}-#{counter}"
    if Set.member?(names, name_counter) do
      find_unique_name(name, names, counter + 1)
    else
      name_counter
    end
  end
end

defimpl HexWeb.Render, for: HexWeb.API.Key do
  import HexWeb.Util

  def render(key) do
    entity =
      key
      |> Map.take([:name, :inserted_at, :updated_at])
      |> Map.update!(:inserted_at, &to_iso8601/1)
      |> Map.update!(:updated_at, &to_iso8601/1)
      |> Map.put(:url, api_url(["keys", key.name]))

    if secret = key.user_secret do
      Map.put(entity, :secret, secret)
    else
      entity
    end
  end
end
