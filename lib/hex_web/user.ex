defmodule HexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  alias HexWeb.Util
  import HexWeb.Validation

  queryable "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    has_many :packages, HexWeb.Package, foreign_key: :owner_id
    has_many :keys, HexWeb.API.Key
    field :created_at, :datetime
    field :updated_at, :datetime
  end

  validatep validate_create(user),
    username: present() and type(:string) and has_format(~r"^[a-z0-9_\-\.!~\*'\(\)]+$", message: "illegal characters"),
    also: unique([:username], on: HexWeb.Repo, case_sensitive: false),
    also: validate_password(),
    also: validate_email()

  validatep validate_email(user),
    email: present() and type(:string) and has_format(~r"^.+@.+\..+$"),
    also: unique([:email], on: HexWeb.Repo)

  validatep validate_password(user),
    password: present() and type(:string)

  def create(username, email, password) do
    username = if is_binary(username), do: String.downcase(username), else: username
    email = if is_binary(email), do: String.downcase(email), else: email
    now = Util.ecto_now
    user = HexWeb.User.new(username: username, email: email, password: password,
                           created_at: now, updated_at: now)

    case validate_create(user) do
      [] ->
        user = user.password(gen_password(password))
        { :ok, HexWeb.Repo.insert(user) }
      errors ->
        { :error, Enum.into(errors, %{}) }
    end
  end

  def update(user, email, password) do
    email = if is_binary(email), do: String.downcase(email), else: email
    errors = []

    if email do
      user = user.email(email)
      errors = errors ++ validate_email(user)
    end

    if password do
      user = user.password(password)
      errors = errors ++ validate_password(user)
    end

    case errors do
      [] ->
        if password, do: user = user.password(gen_password(password))
        user = user.updated_at(Util.ecto_now)
        HexWeb.Repo.update(user)
        { :ok, user }
      errors ->
        { :error, Enum.into(errors, %{}) }
    end
  end

  def get(username) do
    from(u in HexWeb.User, where: downcase(u.username) == downcase(^username), limit: 1)
    |> HexWeb.Repo.all
    |> List.first
  end

  def auth?(nil, _password), do: false

  def auth?(user, password) do
    stored_hash = user.password
    password = List.from_char_data!(password)
    stored_hash = :erlang.binary_to_list(stored_hash)
    { :ok, hash } = :bcrypt.hashpw(password, stored_hash)
    hash == stored_hash
  end

  defp gen_password(password) do
    password      = List.from_char_data!(password)
    work_factor   = HexWeb.Config.password_work_factor
    { :ok, salt } = :bcrypt.gen_salt(work_factor)
    { :ok, hash } = :bcrypt.hashpw(password, salt)
    :erlang.list_to_binary(hash)
  end
end

defimpl HexWeb.Render, for: HexWeb.User.Entity do
  import HexWeb.Util

  def render(user) do
    user.__entity__(:keywords)
    |> Dict.take([:username, :email, :created_at, :updated_at])
    |> Dict.update!(:created_at, &to_iso8601/1)
    |> Dict.update!(:updated_at, &to_iso8601/1)
    |> Dict.put(:url, api_url(["users", user.username]))
    |> Enum.into(%{})
  end
end
