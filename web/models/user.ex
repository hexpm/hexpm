defmodule HexWeb.User do
  use HexWeb.Web, :model

  @timestamps_opts [usec: true]

  @derive {Phoenix.Param, key: :username}

  schema "users" do
    field :username, :string
    field :email, :string
    field :password, :string
    field :confirmation_key, :string
    field :confirmed, :boolean
    timestamps

    field :reset_key, :string
    field :reset_expiry, Ecto.DateTime

    has_many :package_owners, PackageOwner, foreign_key: :owner_id
    has_many :owned_packages, through: [:package_owners, :package]
    has_many :keys, Key
  end

  defp changeset(user, :create, params) do
    cast(user, params, ~w(username password email), [])
    |> update_change(:username, &String.downcase/1)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:username, ~r"^[a-z0-9_\-\.!~\*'\(\)]+$")
    |> validate_format(:email, ~r"^.+@.+\..+$")
    |> unique_constraint(:username, name: "users_username_idx")
    |> unique_constraint(:email, name: "users_email_key")
  end

  defp changeset(user, :update, params) do
    cast(user, params, ~w(username password), [])
    |> update_change(:username, &String.downcase/1)
    |> validate_format(:username, ~r"^[a-z0-9_\-\.!~\*'\(\)]+$")
  end

  def create(params, confirmed? \\ nil) do
    if is_nil(confirmed?) do
      confirmed? = not Application.get_env(:hex_web, :user_confirm)
    end

    changeset(%User{}, :create, params)
    |> put_change(:confirmation_key, gen_key())
    |> put_change(:confirmed, confirmed?)
    |> update_change(:password, &gen_password/1)
  end

  def update(user, params) do
    changeset(user, :update, params)
    |> update_change(:password, &gen_password/1)
  end

  def confirm?(nil, _key),
    do: false
  def confirm?(user, key),
    do: Comeonin.Tools.secure_check(user.confirmation_key, key)

  def confirm(user) do
    change(user, %{confirmed: true})
  end

  def password_reset(user) do
    key = gen_key()
    change(user, %{reset_key: key, reset_expiry: Ecto.DateTime.utc})
  end

  def reset?(nil, _key), do: false
  def reset?(user, key) do
    user.reset_key &&
      Comeonin.Tools.secure_check(user.reset_key, key) &&
      HexWeb.Utils.within_last_day(user.reset_expiry) ||
      false
  end

  # TODO: Move to with when available in ecto
  def reset(user, password) do
    HexWeb.Repo.transaction(fn ->
      user = User.update(user, %{password: password})
             |> HexWeb.Repo.update!

      assoc(user, :keys)
      |> HexWeb.Repo.delete_all

      change(user, %{reset_key: nil, reset_expiry: nil})
      |> HexWeb.Repo.update!
    end)
  end

  def password_auth?(nil, _password), do: false

  def password_auth?(user, password) do
    Comeonin.Bcrypt.checkpw(password, user.password)
  end

  defp gen_password(password) do
    Comeonin.Bcrypt.hashpwsalt(password)
  end

  defp gen_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  # TODO: Move to mailer service
  def send_confirmation_email(user) do
    mailer   = Application.get_env(:hex_web, :email)
    body     = Phoenix.View.render(HexWeb.EmailView, "confirmation_request.html",
                                   layout: {HexWeb.EmailView, "layout.html"},
                                   username: user.username,
                                   key: user.confirmation_key)

    mailer.send(user.email, "Hex.pm - Account confirmation", body)
  end

  # TODO: Move to mailer service
  def send_confirmed_email(user) do
    mailer = Application.get_env(:hex_web, :email)
    body = Phoenix.View.render(HexWeb.EmailView, "confirmed.html",
                               layout: {HexWeb.EmailView, "layout.html"})
    mailer.send(user.email, "Hex.pm - Account confirmed", body)
  end

  # TODO: Move to mailer service
  def send_reset_request_email(user) do
    mailer = Application.get_env(:hex_web, :email)
    body  = Phoenix.View.render(HexWeb.EmailView, "password_reset_request.html",
                                layout: {HexWeb.EmailView, "layout.html"},
                                username: user.username,
                                key: user.reset_key)

    mailer.send(user.email, "Hex.pm - Password reset request", body)
  end

  # TODO: Move to mailer service
  def send_reset_email(user) do
    mailer = Application.get_env(:hex_web, :email)
    body = Phoenix.View.render(HexWeb.EmailView, "password_reset.html",
                               layout: {HexWeb.EmailView, "layout.html"})
    mailer.send(user.email, "Hex.pm - Password reset", body)
  end
end
