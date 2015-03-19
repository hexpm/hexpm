defmodule HexWeb.User do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  alias HexWeb.Util
  import HexWeb.Validation

  schema "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    field :confirmation_key, :string
    field :confirmed, :boolean
    field :created_at, :datetime
    field :updated_at, :datetime

    field :reset_key, :string
    field :reset_expiry, :datetime

    has_many :package_owners, HexWeb.PackageOwner, foreign_key: :owner_id
    has_many :keys, HexWeb.API.Key
  end

  validatep validate_create(user),
    # username: present() and type(:string) and has_format(~r"^[a-z0-9_\-\.!~\*'\(\)]+$", message: "illegal characters"),
    username: present() and has_format(~r"^[a-z0-9_\-\.!~\*'\(\)]+$", message: "illegal characters"),
    also: unique(:username, on: HexWeb.Repo, case_sensitive: false),
    also: validate_password(),
    also: validate_email()

  validatep validate_email(user),
    # email: present() and type(:string) and has_format(~r"^.+@.+\..+$"),
    email: present() and has_format(~r"^.+@.+\..+$"),
    also: unique(:email, on: HexWeb.Repo)

  validatep validate_password(user),
    # password: present() and type(:string)
    password: present()

  def create(username, email, password, confirmed? \\ false) do
    username = if is_binary(username), do: String.downcase(username), else: username
    email    = if is_binary(email),    do: String.downcase(email),    else: email
    now      = Util.ecto_now

    user = %HexWeb.User{username: username, email: email, password: password,
                        created_at: now, updated_at: now, confirmation_key: gen_key(),
                        confirmed: confirmed?}

    if errors = validate_create(user) do
      {:error, errors}
    else
      user = %{user | password: gen_password(password)}
      send_confirmation_email(user)
      {:ok, HexWeb.Repo.insert(user)}
    end
  end

  def update(user, email, password) do
    errors = %{}

    if email do
      user = %{user | email: String.downcase(email)}
      errors = Map.merge(errors, validate_email(user) || %{})
    end

    if password do
      user = %{user | password: password}
      Map.merge(errors, validate_password(user) || %{})
      user = %{user | password: gen_password(password)}
    end

    if errors != %{} do
      {:error, errors}
    else
      user = %{user | updated_at: Util.ecto_now}
      HexWeb.Repo.update(user)
      {:ok, user}
    end
  end

  def confirm?(username, key) do
    if (user = get(username: username)) && Util.secure_compare(user.confirmation_key, key) do
      confirm(user)

      email = Application.get_env(:hex_web, :email)
      body = HexWeb.Email.Templates.render(:confirmed, [])
      email.send(user.email, "Hex.pm - Account confirmed", body)

      true
    else
      false
    end
  end

  def confirm(user) do
    %{user | confirmed: true, updated_at: Util.ecto_now}
    |> HexWeb.Repo.update
  end

  def initiate_password_reset(user) do
    key = gen_key()
    now = Util.ecto_now

    %{user | reset_key: key, reset_expiry: now, updated_at: now}
    |> HexWeb.Repo.update

    send_reset_email(user, key)
  end

  def reset?(username, key, password) do
    if (user = get(username: username))
        && user.reset_key
        && Util.secure_compare(user.reset_key, key)
        && Util.within_last_day(user.reset_expiry) do
      reset(user, password)

      email = Application.get_env(:hex_web, :email)
      body = HexWeb.Email.Templates.render(:password_reset, [])
      email.send(user.email, "Hex.pm - Password reset", body)

      true
    else
      false
    end
  end

  def reset(user, password) do
    HexWeb.Repo.transaction(fn ->
      {:ok, result} = HexWeb.User.update(user, nil, password)

      from(k in HexWeb.API.Key, where: k.user_id == ^result.id)
      |> HexWeb.Repo.delete_all

      %{result | reset_key: nil, reset_expiry: nil, updated_at: Util.ecto_now}
      |> HexWeb.Repo.update
    end)
  end

  def get(username: username) do
    from(u in HexWeb.User,
         where: fragment("lower(?) = lower(?)", u.username, ^username),
         limit: 1)
    |> HexWeb.Repo.all
    |> List.first
  end

  def get(email: email) do
    from(u in HexWeb.User,
         where: u.email == fragment("lower(?)", ^email),
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

  defp gen_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp send_confirmation_email(user) do
    email = Application.get_env(:hex_web, :email)
    body  = HexWeb.Email.Templates.render(:confirmation_request,
                                          username: user.username,
                                          key: user.confirmation_key)

    email.send(user.email, "Hex.pm - Account confirmation", body)
  end

  defp send_reset_email(user, key) do
    email = Application.get_env(:hex_web, :email)
    body  = HexWeb.Email.Templates.render(:password_reset_request,
                                          username: user.username,
                                          key: key)

    email.send(user.email, "Hex.pm - Password reset request", body)
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
