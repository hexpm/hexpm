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
    has_many :audit_logs, AuditLog
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

  def create(params, confirmed? \\ not Application.get_env(:hex_web, :user_confirm)) do
    changeset(%User{}, :create, params)
    |> put_change(:confirmation_key, HexWeb.Auth.gen_key())
    |> put_change(:confirmed, confirmed?)
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def update(user, params) do
    changeset(user, :update, params)
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
    change(user, %{reset_key: key, reset_expiry: Ecto.DateTime.utc})
  end

  def reset?(nil, _key), do: false
  def reset?(user, key) do
    user.reset_key &&
      Comeonin.Tools.secure_check(user.reset_key, key) &&
      HexWeb.Utils.within_last_day(user.reset_expiry) ||
      false
  end

  # TODO: Move to multi when available in ecto
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
end
