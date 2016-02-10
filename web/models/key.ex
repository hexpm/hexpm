defmodule HexWeb.Key do
  use HexWeb.Web, :model

  @derive {Phoenix.Param, key: :name}

  @timestamps_opts [usec: true]

  schema "keys" do
    field :name, :string
    field :secret_first, :string
    field :secret_second, :string
    timestamps

    belongs_to :user, User

    # Only used after key creation to hold the users key (not hashed)
    # the user key will never be retrievable after this
    field :user_secret, :string, virtual: true
  end

  defp changeset(key, params) do
    cast(key, params, ~w(name), [])
    |> add_keys
    |> prepare_changes(&unique_name/1)
  end

  def create(user, params) do
    build_assoc(user, :keys)
    |> changeset(params)
  end

  def all(user) do
    assoc(user, :keys)
  end

  def get(name, user) do
    from(k in assoc(user, :keys), where: k.name == ^name)
  end

  defp gen_key do
    user_secret = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    app_secret  = Application.get_env(:hex_web, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    {user_secret, first, second}
  end

  defp add_keys(changeset) do
    {user_secret, first, second} = gen_key()

    changeset
    |> put_change(:user_secret, user_secret)
    |> put_change(:secret_first, first)
    |> put_change(:secret_second, second)
  end

  defp unique_name(changeset) do
    {:ok, name} = fetch_change(changeset, :name)

    names =
      from(u in assoc(changeset.model, :user),
           join: k in assoc(u, :keys),
           select: k.name)
      |> changeset.repo.all
      |> Enum.into(MapSet.new)

    name = if Set.member?(names, name), do: find_unique_name(name, names), else: name

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
