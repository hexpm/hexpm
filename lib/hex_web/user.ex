defmodule HexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  alias HexWeb.Util
  import HexWeb.Validation

  schema "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    has_many :package_owners, HexWeb.PackageOwner, foreign_key: :owner_id
    has_many :keys, HexWeb.API.Key
    field :created_at, :datetime
    field :updated_at, :datetime

    field :confirmation_key, :string
    field :confirmed, :boolean
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
    email    = if is_binary(email),    do: String.downcase(email),    else: email
    now      = Util.ecto_now
    user     = %HexWeb.User{username: username, email: email, password: password,
                            created_at: now, updated_at: now, confirmation_key: gen_confirmation_key(), confirmed: false}
    case validate_create(user) do
      [] ->
        user = %{user | password: gen_password(password)}
        send_confirmation_email(user)
        {:ok, HexWeb.Repo.insert(user)}
      errors ->
        {:error, Enum.into(errors, %{})}
    end
  end

  def update(user, email, password) do
    errors = []

    if email do
      user = %{user | email: String.downcase(email)}
      errors = errors ++ validate_email(user)
    end

    if password do
      user = %{user | password: password}
      errors = errors ++ validate_password(user)
      user = %{user | password: gen_password(password)}
    end
    case errors do
      [] ->
        user = %{user | updated_at: Util.ecto_now}
        HexWeb.Repo.update(user)
        {:ok, user}
      errors ->
        {:error, Enum.into(errors, %{})}
    end
  end

  def confirm?(username, key) do
    if (user = get(username: username)) && user.confirmation_key == key do
      %{user | confirmed: true, updated_at: Util.ecto_now}
      |> HexWeb.Repo.update

      email = Application.get_env(:hex_web, :email)
      body = HexWeb.Email.render(:confirmed, [])
      email.send(user.email, "Hex.pm - Account confirmed", body)

      true
    else
      false
    end
  end

  def get(username: username) do
    from(u in HexWeb.User,
         where: downcase(u.username) == downcase(^username),
         limit: 1)
    |> HexWeb.Repo.all
    |> List.first
  end

  def get(email: email) do
    from(u in HexWeb.User,
         where: u.email == downcase(^email),
         limit: 1)
    |> HexWeb.Repo.all
    |> List.first
  end

  def delete(user) do
    HexWeb.Repo.delete(user)
  end

  def auth?(nil, _password), do: false

  def auth?(user, password) do
    stored_hash = user.password
    password    = String.to_char_list(password)
    {:ok, hash} = :bcrypt.hashpw(password, stored_hash)
    hash        = :erlang.list_to_binary(hash)

    Util.secure_compare(hash, stored_hash)
  end

  defp gen_password(password) do
    password      = String.to_char_list(password)
    work_factor   = Application.get_env(:hex_web, :password_work_factor)
    {:ok, salt} = :bcrypt.gen_salt(work_factor)
    {:ok, hash} = :bcrypt.hashpw(password, salt)
    :erlang.list_to_binary(hash)
  end

  defp gen_confirmation_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp send_confirmation_email(user) do
    email = Application.get_env(:hex_web, :email)

    body = HexWeb.Email.render(:confirmation_request, username: user.username,
                               key: user.confirmation_key)
    email.send(user.email, "Hex.pm - Account confirmation", body)
  end
end

defimpl HexWeb.Render, for: HexWeb.User do
  import HexWeb.Util

  def render(user) do
    HexWeb.User.__schema__(:keywords, user)
    |> Dict.take([:username, :email, :created_at, :updated_at])
    |> Dict.update!(:created_at, &to_iso8601/1)
    |> Dict.update!(:updated_at, &to_iso8601/1)
    |> Dict.put(:url, api_url(["users", user.username]))
    |> Enum.into(%{})
  end
end
