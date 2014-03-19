defmodule HexWeb.Key do
  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation

  queryable "keys" do
    belongs_to :user, HexWeb.User
    field :name, :string
    field :secret, :string
    field :created, :datetime
  end

  validatep validate(key),
    name: present() and type(:string)

  def create(name, user) do
    key = user.keys.new(name: name)

    case validate(key) do
      [] ->
        names =
          from(k in HexWeb.Key, where: k.user_id == ^user.id, select: k.name)
          |> HexWeb.Repo.all
          |> HashSet.new

        if Set.member?(names, name) do
          name = unique_name(name, names)
        end

        secret = :crypto.strong_rand_bytes(16) |> HexWeb.Util.hexify
        key = key.name(name).secret(secret)
        { :ok, HexWeb.Repo.create(key) }
      errors ->
        { :error, errors }
    end
  end

  def all(user) do
    from(k in HexWeb.Key, where: k.user_id == ^user.id)
    |> HexWeb.Repo.all
  end

  def get(name, user) do
    from(k in HexWeb.Key, where: k.user_id == ^user.id and k.name == ^name)
    |> HexWeb.Repo.all
    |> List.first
  end

  def delete(key) do
    HexWeb.Repo.delete(key)
    :ok
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

defimpl HexWeb.Render, for: HexWeb.Key.Entity do
  import HexWeb.Util

  def render(key) do
    key.__entity__(:keywords)
    |> Dict.take([:name, :secret, :created])
    |> Dict.update!(:created, &to_iso8601/1)
    |> Dict.put(:url, api_url(["keys", key.name]))
  end
end
