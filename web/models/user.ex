defmodule HexWeb.User do
  use HexWeb.Web, :model

  @derive {Phoenix.Param, key: :username}

  schema "users" do
    field :username, :string
    field :full_name, :string
    field :email, :string
    field :password, :string
    field :confirmation_key, :string
    field :confirmed, :boolean
    timestamps()

    field :reset_key, :string
    field :reset_expiry, :naive_datetime

    has_many :package_owners, PackageOwner, foreign_key: :owner_id
    has_many :owned_packages, through: [:package_owners, :package]
    has_many :keys, Key
    has_many :audit_logs, AuditLog, foreign_key: :actor_id
  end

  @email_regex ~r"^.+@.+\..+$"
  @username_regex ~r"^[a-z0-9_\-\.!~\*'\(\)]+$"

  # TODO: Make full_name required
  defp changeset(user, :create, params) do
    cast(user, params, ~w(username full_name password email))
    |> validate_required(~w(username password email)a)
    |> update_change(:email, &String.downcase/1)
    |> update_change(:username, &String.downcase/1)
    |> validate_format(:email, @email_regex)
    |> validate_format(:username, @username_regex)
    |> unique_constraint(:email, name: "users_email_key")
    |> unique_constraint(:username, name: "users_username_idx")
  end

  defp changeset(user, :update, params) do
    cast(user, params, ~w(username full_name password))
    |> validate_required(~w(username password)a)
    |> update_change(:username, &String.downcase/1)
    |> validate_format(:username, @username_regex)
  end

  def build(params, confirmed? \\ not Application.get_env(:hex_web, :user_confirm)) do
    changeset(%User{}, :create, params)
    |> put_change(:confirmation_key, HexWeb.Auth.gen_key())
    |> put_change(:confirmed, confirmed?)
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def update_profile(user, params) do
    cast(user, params, ~w(full_name))
    |> validate_required(~w(full_name)a)
  end

  def update_password(user, params) do
    cast(user, params, ~w(password))
    |> validate_required(~w(password)a)
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def confirm?(nil, _key),
    do: false
  def confirm?(user, key),
    do: Comeonin.Tools.secure_check(user.confirmation_key, key)

  def confirm(user) do
    change(user, %{confirmed: true})
  end

  def password_reset(user) do
    key = HexWeb.Auth.gen_key()
    change(user, %{reset_key: key, reset_expiry: HexWeb.Utils.utc_now})
  end

  def reset?(nil, _key), do: false
  def reset?(user, key) do
    user.reset_key &&
      Comeonin.Tools.secure_check(user.reset_key, key) &&
      HexWeb.Utils.within_last_day(user.reset_expiry) ||
      false
  end

  def reset(user, password, revoke_all_keys \\ true) do
    multi = Ecto.Multi.new
    |> Ecto.Multi.update(:password, update_password(user, %{password: password}))
    |> Ecto.Multi.update(:reset, change(user, %{reset_key: nil, reset_expiry: nil}))
    if revoke_all_keys do
      multi
      |> Ecto.Multi.update_all(:keys, Key.revoke_all(user), [])
    else
      multi
    end
  end
end
