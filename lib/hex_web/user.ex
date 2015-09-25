defmodule HexWeb.User do
  use Ecto.Model
  alias HexWeb.Util
  import Ecto.Changeset, except: [validate_unique: 3]
  import HexWeb.Validation

  @timestamps_opts [usec: true]

  schema "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    field :confirmation_key, :string
    field :confirmed, :boolean
    timestamps

    field :reset_key, :string
    field :reset_expiry, Ecto.DateTime

    has_many :package_owners, HexWeb.PackageOwner, foreign_key: :owner_id
    has_many :keys, HexWeb.API.Key
  end

  before_delete :delete_keys
  before_delete :delete_owners

  defp changeset(user, :create, params) do
    cast(user, params, ~w(username password email), [])
    |> update_change(:username, &String.downcase/1)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:username, ~r"^[a-z0-9_\-\.!~\*'\(\)]+$")
    |> validate_format(:email, ~r"^.+@.+\..+$")
    |> validate_unique(:username, on: HexWeb.Repo)
    |> validate_unique(:email, on: HexWeb.Repo)
  end

  defp changeset(user, :update, params) do
    cast(user, params, ~w(username password), [])
    |> update_change(:username, &String.downcase/1)
    |> validate_format(:username, ~r"^[a-z0-9_\-\.!~\*'\(\)]+$")
  end

  def create(params, confirmed? \\ false) do
    changeset =
      changeset(%HexWeb.User{}, :create, params)
      |> put_change(:confirmation_key, gen_key())
      |> put_change(:confirmed, confirmed?)
      |> update_change(:password, &gen_password/1)

    if changeset.valid? do
      send_confirmation_email(changeset)
      {:ok, HexWeb.Repo.insert(changeset)}
    else
      {:error, changeset.errors}
    end
  end

  def update(user, params) do
    changeset =
      changeset(user, :update, params)
      |> update_change(:password, &gen_password/1)

    if changeset.valid? do
      {:ok, HexWeb.Repo.update(changeset)}
    else
      {:error, changeset.errors}
    end
  end

  def confirm?(username, key) do
    if (user = get(username: username)) && Comeonin.Tools.secure_check(user.confirmation_key, key) do
      confirm(user)

      mailer = Application.get_env(:hex_web, :email)
      body = HexWeb.Email.Templates.render(:confirmed, [])
      mailer.send(user.email, "Hex.pm - Account confirmed", body)

      true
    else
      false
    end
  end

  def confirm(user) do
    change(user, %{confirmed: true})
    |> HexWeb.Repo.update
  end

  def password_reset(user) do
    key = gen_key()
    send_reset_email(user, key)

    change(user, %{reset_key: key, reset_expiry: Ecto.DateTime.utc})
    |> HexWeb.Repo.update
  end

  def reset?(username, key, password) do
    if (user = get(username: username))
        && user.reset_key
        && Comeonin.Tools.secure_check(user.reset_key, key)
        && Util.within_last_day(user.reset_expiry) do
      reset(user, password)

      mailer = Application.get_env(:hex_web, :email)
      body = HexWeb.Email.Templates.render(:password_reset, [])
      mailer.send(user.email, "Hex.pm - Password reset", body)

      true
    else
      false
    end
  end

  def reset(user, password) do
    HexWeb.Repo.transaction(fn ->
      {:ok, user} = HexWeb.User.update(user, %{password: password})

      assoc(user, :keys)
      |> HexWeb.Repo.delete_all

      change(user, %{reset_key: nil, reset_expiry: nil})
      |> HexWeb.Repo.update
    end)
  end

  def get(username: username) do
    from(u in HexWeb.User,
         where: u.username == ^username,
         limit: 1)
    |> HexWeb.Repo.one
  end

  def get(email: email) do
    from(u in HexWeb.User,
         where: u.email == ^email,
         limit: 1)
    |> HexWeb.Repo.one
  end

  def delete(user) do
    HexWeb.Repo.delete(user)
  end

  def auth?(nil, _password), do: false

  def auth?(user, password) do
    Comeonin.Bcrypt.checkpw(password, user.password)
  end

  defp delete_keys(changeset) do
    assoc(changeset.model, :keys)
    |> HexWeb.Repo.delete_all
    changeset
  end

  defp delete_owners(changeset) do
    assoc(changeset.model, :package_owners)
    |> HexWeb.Repo.delete_all
    changeset
  end

  defp gen_password(password) do
    Comeonin.Bcrypt.hashpwsalt(password)
  end

  defp gen_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp send_confirmation_email(changeset) do
    username = get_change(changeset, :username)
    email    = get_change(changeset, :email)
    key      = get_change(changeset, :confirmation_key)
    mailer   = Application.get_env(:hex_web, :email)
    body     = HexWeb.Email.Templates.render(:confirmation_request, username: username, key: key)

    mailer.send(email, "Hex.pm - Account confirmation", body)
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
    user
    |> Map.take([:username, :email, :inserted_at, :updated_at])
    |> Map.update!(:inserted_at, &to_iso8601/1)
    |> Map.update!(:updated_at, &to_iso8601/1)
    |> Map.put(:url, api_url(["users", user.username]))
  end
end
